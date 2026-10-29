// zeig7z.cpp — the C interface in zeig7z.h, on top of 7-Zip's COM-style C++ API.
//
// SPDX-License-Identifier: LGPL-2.1-or-later
// Adapted from 7-Zip's CPP/7zip/UI/Client7z/Client7z.cpp (Igor Pavlov, LGPL). Changes: a C
// API instead of a command line, handlers linked in statically instead of loaded from 7z.so,
// format detection by signature, split-volume opening, path sanitizing on extraction,
// recursive folder adding, compression properties, progress and cancellation.
//
// How the pieces fit (see Native/zeig7z/README.md for the long version):
// - 7-Zip's archive handlers register themselves in a table when the program starts.
//   GetNumberOfFormats / GetHandlerProperty2 / GetIsArc / CreateObject (from
//   Archive/ArchiveExports.cpp and DllExports2.cpp) read that table. The build links all of
//   7-Zip into one object file so none of the handlers are dropped by the linker.
// - Reading: CreateObject(format CLSID, IID_IInArchive) → IInArchive::Open(stream, callback)
//   → GetNumberOfItems / GetProperty(index, kpid…) → Extract(indices, testMode, callback).
//   7-Zip "pulls": it calls our callback objects for passwords, volumes, output streams and
//   progress.
// - Writing: CreateObject(CLSID, IID_IOutArchive) → ISetProperties::SetProperties(-m options)
//   → UpdateItems(out stream, item count, callback). The update callback describes each item
//   (GetProperty) and hands 7-Zip an input stream for it (GetStream).

#include <dirent.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <mutex>
#include <string>
#include <vector>

// 7-Zip's own sources include Common.h first (through StdAfx.h); do the same.
#include "Common/Common.h"
#include "Common/MyWindows.h"
#include "Common/MyCom.h"
#include "Common/MyString.h"
#include "Common/StringConvert.h"
#include "Common/UTFConvert.h"
#include "Windows/FileDir.h"
#include "Windows/PropVariant.h"
#include "Windows/TimeUtils.h"
#include "7zip/Common/FileStreams.h"
#include "7zip/Common/StreamUtils.h"
#include "7zip/Archive/IArchive.h"
#include "7zip/IPassword.h"
#include "../C/7zVersion.h"

#include "zeig7z.h"

using namespace NWindows;

// From 7-Zip's ArchiveExports.cpp / DllExports2.cpp, linked in statically.
STDAPI CreateObject(const GUID *clsid, const GUID *iid, void **outObject);
STDAPI GetNumberOfFormats(UINT32 *numFormats);
STDAPI GetHandlerProperty2(UInt32 formatIndex, PROPID propID, PROPVARIANT *value);
STDAPI GetIsArc(UInt32 formatIndex, Func_IsArc *isArc);

// MARK: - Errors

static thread_local std::string g_lastError;

static zeig7z_result fail(zeig7z_result result, const std::string &message)
{
    g_lastError = message;
    return result;
}

extern "C" const char *zeig7z_last_error(void) { return g_lastError.c_str(); }

extern "C" const char *zeig7z_version(void) { return MY_VERSION_NUMBERS; }

// MARK: - Strings

static UString utf8ToUnicode(const char *s)
{
    UString result;
    if (s)
        ConvertUTF8ToUnicode(AString(s), result);
    return result;
}

static std::string unicodeToUtf8(const UString &s)
{
    AString result;
    ConvertUnicodeToUTF8(s, result);
    return std::string(result.Ptr(), result.Len());
}

// File-system paths. On Apple platforms FString is a byte string (AString) holding the path
// exactly as the OS takes it: UTF-8. 7-Zip's own us2fs/fs2us go through the C locale and
// mangle non-ASCII names, so the bridge never uses them.
static FString utf8ToFString(const char *s) { return FString(s ? s : ""); }

static FString unicodeToFString(const UString &s)
{
    AString result;
    ConvertUnicodeToUTF8(s, result);
    return result;
}

static bool equalsIgnoringCase(const std::string &a, const std::string &b)
{
    return a.size() == b.size() && strncasecmp(a.c_str(), b.c_str(), a.size()) == 0;
}

// MARK: - Format registry

namespace {

struct Format
{
    std::string name;
    std::string extensions;
    bool canWrite = false;
    GUID classID;
    // How detection recognizes the format: fixed byte signatures at `signatureOffset`, and/or
    // an IsArc function for formats whose header needs a closer look.
    std::vector<std::string> signatures;
    UInt32 signatureOffset = 0;
    Func_IsArc isArc = NULL;
};

/// A handler property that holds raw bytes in a BSTR (class IDs, signatures).
std::string rawProperty(UInt32 index, PROPID id)
{
    NCOM::CPropVariant prop;
    if (GetHandlerProperty2(index, id, &prop) != S_OK || prop.vt != VT_BSTR || !prop.bstrVal)
        return std::string();
    return std::string((const char *)prop.bstrVal, SysStringByteLen(prop.bstrVal));
}

const std::vector<Format> &formats()
{
    static std::vector<Format> table;
    static std::once_flag once;
    std::call_once(once, [] {
        UINT32 count = 0;
        GetNumberOfFormats(&count);
        for (UInt32 i = 0; i < count; i++)
        {
            Format f;
            NCOM::CPropVariant prop;
            if (GetHandlerProperty2(i, NArchive::NHandlerPropID::kName, &prop) == S_OK && prop.vt == VT_BSTR)
                f.name = unicodeToUtf8(prop.bstrVal);
            prop.Clear();
            if (GetHandlerProperty2(i, NArchive::NHandlerPropID::kExtension, &prop) == S_OK && prop.vt == VT_BSTR)
                f.extensions = unicodeToUtf8(prop.bstrVal);
            prop.Clear();
            if (GetHandlerProperty2(i, NArchive::NHandlerPropID::kUpdate, &prop) == S_OK && prop.vt == VT_BOOL)
                f.canWrite = VARIANT_BOOLToBool(prop.boolVal);
            prop.Clear();
            const std::string classID = rawProperty(i, NArchive::NHandlerPropID::kClassID);
            if (classID.size() != sizeof(GUID))
                continue;
            memcpy(&f.classID, classID.data(), sizeof(GUID));
            const std::string signature = rawProperty(i, NArchive::NHandlerPropID::kSignature);
            if (!signature.empty())
                f.signatures.push_back(signature);
            else
            {
                // Several signatures: each is a length byte followed by that many bytes.
                const std::string multi = rawProperty(i, NArchive::NHandlerPropID::kMultiSignature);
                for (size_t at = 0; at < multi.size();)
                {
                    const size_t length = (unsigned char)multi[at++];
                    if (at + length > multi.size())
                        break;
                    f.signatures.push_back(multi.substr(at, length));
                    at += length;
                }
            }
            if (GetHandlerProperty2(i, NArchive::NHandlerPropID::kSignatureOffset, &prop) == S_OK && prop.vt == VT_UI4)
                f.signatureOffset = prop.ulVal;
            prop.Clear();
            GetIsArc(i, &f.isArc);
            table.push_back(f);
        }
    });
    return table;
}

const Format *formatNamed(const std::string &name)
{
    for (const Format &f : formats())
        if (equalsIgnoringCase(f.name, name))
            return &f;
    return NULL;
}

} // namespace

extern "C" uint32_t zeig7z_format_count(void) { return (uint32_t)formats().size(); }

extern "C" zeig7z_result zeig7z_format_at(uint32_t index, zeig7z_format_info *out)
{
    if (!out || index >= formats().size())
        return fail(ZEIG7Z_INVALID_ARGUMENT, "format index out of range");
    const Format &f = formats()[index];
    out->name = f.name.c_str();
    out->extensions = f.extensions.c_str();
    out->can_write = f.canWrite ? 1 : 0;
    return ZEIG7Z_OK;
}

// MARK: - Progress

namespace {

// Shared by the open, extract and update callbacks: forwards IProgress to the C callback
// and remembers whether the user cancelled, so E_ABORT can be reported as ZEIG7Z_CANCELLED.
struct ProgressRelay
{
    const zeig7z_callbacks *callbacks = NULL;
    UInt64 total = 0;
    bool cancelled = false;

    HRESULT setTotal(UInt64 value)
    {
        total = value;
        return S_OK;
    }

    HRESULT setCompleted(const UInt64 *value)
    {
        if (!callbacks || !callbacks->progress || !value)
            return S_OK;
        if (callbacks->progress(callbacks->context, *value, total) != 0)
        {
            cancelled = true;
            return E_ABORT;
        }
        return S_OK;
    }
};

// MARK: - Open callback

// Supplies the header password and, for split archives, the other volumes.
class COpenCallback Z7_final:
    public IArchiveOpenCallback,
    public IArchiveOpenVolumeCallback,
    public ICryptoGetTextPassword,
    public CMyUnknownImp
{
    Z7_IFACES_IMP_UNK_3(IArchiveOpenCallback, IArchiveOpenVolumeCallback, ICryptoGetTextPassword)

public:
    FString directory;   // with trailing '/'
    UString fileName;    // the volume 7-Zip asks about with GetProperty(kpidName)
    UString password;
    bool hasPassword = false;
    bool passwordWasAsked = false;
};

Z7_COM7F_IMF(COpenCallback::SetTotal(const UInt64 *, const UInt64 *)) { return S_OK; }
Z7_COM7F_IMF(COpenCallback::SetCompleted(const UInt64 *, const UInt64 *)) { return S_OK; }

Z7_COM7F_IMF(COpenCallback::GetProperty(PROPID propID, PROPVARIANT *value))
{
    NCOM::CPropVariant prop;
    if (propID == kpidName)
        prop = fileName;
    prop.Detach(value);
    return S_OK;
}

Z7_COM7F_IMF(COpenCallback::GetStream(const wchar_t *name, IInStream **inStream))
{
    *inStream = NULL;
    // Volumes are always siblings of the first one; refuse anything that tries to leave
    // the folder.
    UString volume(name);
    if (volume.Find(L'/') >= 0)
        return S_FALSE;
    CInFileStream *spec = new CInFileStream;
    CMyComPtr<IInStream> stream(spec);
    if (!spec->Open(directory + unicodeToFString(volume)))
        return S_FALSE;
    *inStream = stream.Detach();
    return S_OK;
}

Z7_COM7F_IMF(COpenCallback::CryptoGetTextPassword(BSTR *result))
{
    passwordWasAsked = true;
    if (!hasPassword)
        return E_ABORT;
    return StringToBstr(password, result);
}

} // namespace

// MARK: - Archive handle

struct zeig7z_archive
{
    CMyComPtr<IInArchive> handler;
    std::string formatName;
    std::string fallbackName;  // name for single-stream formats that store none (gzip, xz)
    std::string pathBuffer;    // backs zeig7z_entry.path
    std::string methodBuffer;  // backs zeig7z_archive_info.method
    std::string commentBuffer; // backs zeig7z_archive_info.comment
    UString password;
    bool hasPassword = false;
};

static zeig7z_result openWith(const Format &format, const FString &path, COpenCallback *callbackSpec,
                              CMyComPtr<IInArchive> &result, HRESULT &hr)
{
    CMyComPtr<IInArchive> handler;
    hr = CreateObject(&format.classID, &IID_IInArchive, (void **)&handler);
    if (hr != S_OK || !handler)
        return ZEIG7Z_UNSUPPORTED_FORMAT;
    CInFileStream *fileSpec = new CInFileStream;
    CMyComPtr<IInStream> file(fileSpec);
    if (!fileSpec->Open(path))
        return ZEIG7Z_IO_ERROR;
    CMyComPtr<IArchiveOpenCallback> callback(callbackSpec);
    const UInt64 scanSize = 1 << 23;
    hr = handler->Open(file, &scanSize, callback);
    if (hr == S_OK)
    {
        result = handler;
        return ZEIG7Z_OK;
    }
    handler->Close();
    return ZEIG7Z_UNSUPPORTED_FORMAT;
}

/// Formats that recognize the start of the file: exact signature matches first, then IsArc
/// "yes", then IsArc "need more data" (signatures deeper than the bytes read), each in
/// registry order.
static std::vector<const Format *> formatsMatchingSignature(const FString &path)
{
    std::vector<const Format *> sure, probable, possible;
    CInFileStream *spec = new CInFileStream;
    CMyComPtr<IInStream> stream(spec);
    if (!spec->Open(path))
        return sure;
    // Enough for signatures that sit far into the file (ISO's is at 32 KiB).
    std::vector<Byte> buffer(1 << 16);
    size_t size = buffer.size();
    if (ReadStream(stream, buffer.data(), &size) != S_OK)
        return sure;
    for (const Format &f : formats())
    {
        bool matched = false;
        for (const std::string &signature : f.signatures)
            if (!signature.empty() && f.signatureOffset + signature.size() <= size
                && memcmp(buffer.data() + f.signatureOffset, signature.data(), signature.size()) == 0)
                matched = true;
        if (matched)
        {
            sure.push_back(&f);
            continue;
        }
        if (!f.isArc)
            continue;
        const UInt32 result = f.isArc(buffer.data(), size);
        if (result == k_IsArc_Res_YES)
            probable.push_back(&f);
        else if (result == k_IsArc_Res_NEED_MORE)
            possible.push_back(&f);
    }
    sure.insert(sure.end(), probable.begin(), probable.end());
    sure.insert(sure.end(), possible.begin(), possible.end());
    return sure;
}

static std::string defaultEntryName(const std::string &archivePath)
{
    std::string name = archivePath.substr(archivePath.find_last_of('/') + 1);
    const size_t dot = name.find_last_of('.');
    if (dot == std::string::npos || dot == 0)
        return name;
    const std::string ext = name.substr(dot + 1);
    name.erase(dot);
    if (equalsIgnoringCase(ext, "tgz") || equalsIgnoringCase(ext, "tbz") || equalsIgnoringCase(ext, "tbz2")
        || equalsIgnoringCase(ext, "txz") || equalsIgnoringCase(ext, "tzst"))
        name += ".tar";
    return name;
}

extern "C" zeig7z_result zeig7z_open(const char *path, const char *formatList, const char *password,
                                     zeig7z_archive **out)
{
    if (!path || !out)
        return fail(ZEIG7Z_INVALID_ARGUMENT, "path and out must not be NULL");
    *out = NULL;
    const FString fsPath = utf8ToFString(path);

    std::vector<const Format *> candidates;
    if (formatList && *formatList)
    {
        std::string list(formatList);
        size_t start = 0;
        while (start <= list.size())
        {
            size_t comma = list.find(',', start);
            if (comma == std::string::npos)
                comma = list.size();
            const std::string name = list.substr(start, comma - start);
            if (const Format *f = formatNamed(name))
                candidates.push_back(f);
            else if (!name.empty())
                return fail(ZEIG7Z_UNSUPPORTED_FORMAT, "7-Zip has no format named " + name);
            start = comma + 1;
        }
    }
    else
        candidates = formatsMatchingSignature(fsPath);
    if (candidates.empty())
        return fail(ZEIG7Z_UNSUPPORTED_FORMAT, "7-Zip doesn't recognize this file");

    const std::string pathString(path);
    const size_t slash = pathString.find_last_of('/');
    bool passwordAsked = false;
    for (const Format *format : candidates)
    {
        COpenCallback *callbackSpec = new COpenCallback;
        CMyComPtr<IArchiveOpenCallback> keepAlive(callbackSpec);
        callbackSpec->directory = utf8ToFString(pathString.substr(0, slash + 1).c_str());
        callbackSpec->fileName = utf8ToUnicode(pathString.substr(slash + 1).c_str());
        callbackSpec->hasPassword = password != NULL;
        callbackSpec->password = utf8ToUnicode(password);

        CMyComPtr<IInArchive> handler;
        HRESULT hr = S_OK;
        const zeig7z_result r = openWith(*format, fsPath, callbackSpec, handler, hr);
        if (r == ZEIG7Z_IO_ERROR)
            return fail(r, "can't read the archive file");
        if (r == ZEIG7Z_OK)
        {
            zeig7z_archive *archive = new zeig7z_archive;
            archive->handler = handler;
            archive->formatName = format->name;
            archive->fallbackName = defaultEntryName(pathString);
            archive->hasPassword = password != NULL;
            archive->password = utf8ToUnicode(password);
            *out = archive;
            g_lastError.clear();
            return ZEIG7Z_OK;
        }
        passwordAsked = passwordAsked || callbackSpec->passwordWasAsked;
        if (hr == E_OUTOFMEMORY)
            return fail(ZEIG7Z_OUT_OF_MEMORY, "out of memory opening the archive");
    }
    if (passwordAsked)
        return fail(ZEIG7Z_WRONG_PASSWORD, password ? "the password is wrong" : "the archive needs a password");
    if (!formatList || !*formatList)
        return fail(ZEIG7Z_UNSUPPORTED_FORMAT, "7-Zip doesn't recognize this file");
    return fail(ZEIG7Z_CORRUPT_ARCHIVE, "7-Zip can't open this file as " + candidates.front()->name);
}

extern "C" void zeig7z_close(zeig7z_archive *archive)
{
    if (!archive)
        return;
    if (archive->handler)
        archive->handler->Close();
    delete archive;
}

extern "C" const char *zeig7z_archive_format(const zeig7z_archive *archive)
{
    return archive ? archive->formatName.c_str() : "";
}

extern "C" uint32_t zeig7z_entry_count(const zeig7z_archive *archive)
{
    if (!archive)
        return 0;
    UInt32 count = 0;
    archive->handler->GetNumberOfItems(&count);
    return count;
}

// MARK: - Entry properties

static bool boolProperty(IInArchive *handler, UInt32 index, PROPID id)
{
    NCOM::CPropVariant prop;
    if (handler->GetProperty(index, id, &prop) != S_OK)
        return false;
    return prop.vt == VT_BOOL && VARIANT_BOOLToBool(prop.boolVal);
}

static bool uint64Property(IInArchive *handler, UInt32 index, PROPID id, UInt64 &value)
{
    NCOM::CPropVariant prop;
    if (handler->GetProperty(index, id, &prop) != S_OK)
        return false;
    switch (prop.vt)
    {
        case VT_UI8: value = prop.uhVal.QuadPart; return true;
        case VT_UI4: value = prop.ulVal; return true;
        case VT_UI2: value = prop.uiVal; return true;
        default: return false;
    }
}

/// Unix mode bits, from kpidPosixAttrib or the high half of a Windows attribute word.
static bool posixMode(IInArchive *handler, UInt32 index, UInt32 &mode)
{
    UInt64 value = 0;
    if (uint64Property(handler, index, kpidPosixAttrib, value))
    {
        mode = (UInt32)value;
        return true;
    }
    if (uint64Property(handler, index, kpidAttrib, value) && (value & FILE_ATTRIBUTE_UNIX_EXTENSION))
    {
        mode = (UInt32)(value >> 16);
        return true;
    }
    return false;
}

static bool isSymlink(IInArchive *handler, UInt32 index)
{
    UInt32 mode = 0;
    if (posixMode(handler, index, mode) && S_ISLNK(mode))
        return true;
    NCOM::CPropVariant prop;
    return handler->GetProperty(index, kpidSymLink, &prop) == S_OK && prop.vt == VT_BSTR;
}

static UString entryPath(const zeig7z_archive *archive, UInt32 index)
{
    NCOM::CPropVariant prop;
    if (archive->handler->GetProperty(index, kpidPath, &prop) == S_OK && prop.vt == VT_BSTR)
        return UString(prop.bstrVal);
    return utf8ToUnicode(archive->fallbackName.c_str());
}

extern "C" zeig7z_result zeig7z_entry_at(zeig7z_archive *archive, uint32_t index, zeig7z_entry *out)
{
    if (!archive || !out || index >= zeig7z_entry_count(archive))
        return fail(ZEIG7Z_INVALID_ARGUMENT, "entry index out of range");
    IInArchive *handler = archive->handler;
    memset(out, 0, sizeof(*out));

    archive->pathBuffer = unicodeToUtf8(entryPath(archive, index));
    out->path = archive->pathBuffer.c_str();
    UInt64 value = 0;
    if (uint64Property(handler, index, kpidSize, value))
        out->size = value;
    if (uint64Property(handler, index, kpidPackSize, value))
        out->packed_size = value;
    {
        NCOM::CPropVariant prop;
        if (handler->GetProperty(index, kpidMTime, &prop) == S_OK && prop.vt == VT_FILETIME)
        {
            out->modified = NTime::FileTime_To_UnixTime64(prop.filetime);
            out->has_modified = 1;
        }
    }
    out->is_directory = boolProperty(handler, index, kpidIsDir) ? 1 : 0;
    out->is_encrypted = boolProperty(handler, index, kpidEncrypted) ? 1 : 0;
    out->is_symlink = isSymlink(handler, index) ? 1 : 0;
    return ZEIG7Z_OK;
}

// MARK: - Archive properties

static std::string archiveString(IInArchive *handler, PROPID id)
{
    NCOM::CPropVariant prop;
    if (handler->GetArchiveProperty(id, &prop) == S_OK && prop.vt == VT_BSTR)
        return unicodeToUtf8(prop.bstrVal);
    return std::string();
}

extern "C" zeig7z_result zeig7z_get_archive_info(zeig7z_archive *archive, zeig7z_archive_info *out)
{
    if (!archive || !out)
        return fail(ZEIG7Z_INVALID_ARGUMENT, "archive and out must not be NULL");
    IInArchive *handler = archive->handler;
    memset(out, 0, sizeof(*out));

    archive->methodBuffer = archiveString(handler, kpidMethod);
    if (archive->methodBuffer.empty() && zeig7z_entry_count(archive) > 0)
    {
        // zip, rar and others record the method per entry: report the largest file's. (Folders
        // and empty files are "Store", which says nothing about the archive.)
        const uint32_t count = zeig7z_entry_count(archive);
        UInt64 largest = 0;
        bool found = false;
        for (uint32_t i = 0; i < count; i++)
        {
            if (boolProperty(handler, i, kpidIsDir))
                continue;
            UInt64 size = 0;
            uint64Property(handler, i, kpidSize, size);
            if (found && size <= largest)
                continue;
            NCOM::CPropVariant prop;
            if (handler->GetProperty(i, kpidMethod, &prop) == S_OK && prop.vt == VT_BSTR)
            {
                archive->methodBuffer = unicodeToUtf8(prop.bstrVal);
                largest = size;
                found = true;
            }
        }
    }
    out->method = archive->methodBuffer.c_str();

    out->solid = -1;
    {
        NCOM::CPropVariant prop;
        if (handler->GetArchiveProperty(kpidSolid, &prop) == S_OK && prop.vt == VT_BOOL)
            out->solid = VARIANT_BOOLToBool(prop.boolVal) ? 1 : 0;
    }
    {
        NCOM::CPropVariant prop;
        if (handler->GetArchiveProperty(kpidPhySize, &prop) == S_OK)
        {
            if (prop.vt == VT_UI8) out->physical_size = prop.uhVal.QuadPart;
            else if (prop.vt == VT_UI4) out->physical_size = prop.ulVal;
        }
    }
    {
        NCOM::CPropVariant prop;
        if (handler->GetArchiveProperty(kpidNumVolumes, &prop) == S_OK && prop.vt == VT_UI4)
            out->volume_count = prop.ulVal;
    }
    archive->commentBuffer = archiveString(handler, kpidComment);
    out->comment = archive->commentBuffer.c_str();
    return ZEIG7Z_OK;
}

// MARK: - Extraction

/// Drops empty, "." and ".." components and any leading '/', so the result is always a
/// relative path under the destination. Empty when nothing is left.
static UString sanitizedRelativePath(const UString &path)
{
    UString result;
    UString part;
    const unsigned length = path.Len();
    for (unsigned i = 0; i <= length; i++)
    {
        const wchar_t c = i < length ? path[i] : L'/';
        if (c != L'/' && c != L'\\')
        {
            part += c;
            continue;
        }
        if (!part.IsEmpty() && !part.IsEqualTo(".") && !part.IsEqualTo(".."))
        {
            if (!result.IsEmpty())
                result += L'/';
            result += part;
        }
        part.Empty();
    }
    return result;
}

namespace {

class CExtractCallback Z7_final:
    public IArchiveExtractCallback,
    public ICryptoGetTextPassword,
    public CMyUnknownImp
{
    Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
    Z7_IFACE_COM7_IMP(IProgress)

public:
    zeig7z_archive *archive = NULL;
    FString destination;  // with trailing '/'
    UString password;
    bool hasPassword = false;
    ProgressRelay progress;

    // The first problem seen; extraction carries on so the other files still come out.
    zeig7z_result firstError = ZEIG7Z_OK;
    std::string firstErrorMessage;

private:
    COutFileStream *_outSpec = NULL;
    CMyComPtr<ISequentialOutStream> _out;
    FString _outPath;
    UString _entryPath;
    bool _hasMTime = false;
    FILETIME _mtime;
    bool _hasMode = false;
    UInt32 _mode = 0;
    bool _encrypted = false;

    void note(zeig7z_result result, const std::string &message)
    {
        if (firstError == ZEIG7Z_OK)
        {
            firstError = result;
            firstErrorMessage = message;
        }
    }
};

Z7_COM7F_IMF(CExtractCallback::SetTotal(UInt64 size)) { return progress.setTotal(size); }
Z7_COM7F_IMF(CExtractCallback::SetCompleted(const UInt64 *value)) { return progress.setCompleted(value); }

Z7_COM7F_IMF(CExtractCallback::GetStream(UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode))
{
    *outStream = NULL;
    _out.Release();
    _outSpec = NULL;
    IInArchive *handler = archive->handler;
    _entryPath = entryPath(archive, index);
    _encrypted = boolProperty(handler, index, kpidEncrypted);

    if (askExtractMode != NArchive::NExtract::NAskMode::kExtract)
        return S_OK;  // testing: 7-Zip decodes and checks without an output stream

    const UString relative = sanitizedRelativePath(_entryPath);
    if (relative.IsEmpty() || isSymlink(handler, index))
        return S_OK;  // nothing safe to write; the data is skipped

    _outPath = destination + unicodeToFString(relative);
    {
        NCOM::CPropVariant prop;
        _hasMTime = handler->GetProperty(index, kpidMTime, &prop) == S_OK && prop.vt == VT_FILETIME;
        if (_hasMTime)
            _mtime = prop.filetime;
    }
    _hasMode = posixMode(handler, index, _mode);

    if (boolProperty(handler, index, kpidIsDir))
    {
        if (!NFile::NDir::CreateComplexDir(_outPath))
            note(ZEIG7Z_IO_ERROR, "can't create folder " + unicodeToUtf8(relative));
        return S_OK;
    }
    const int slash = relative.ReverseFind(L'/');
    if (slash >= 0)
        NFile::NDir::CreateComplexDir(destination + unicodeToFString(relative.Left((unsigned)slash)));

    // Replace an existing file rather than writing through it (it might be a link).
    unlink(_outPath.Ptr());
    _outSpec = new COutFileStream;
    CMyComPtr<ISequentialOutStream> stream(_outSpec);
    if (!_outSpec->Create_ALWAYS(_outPath))
    {
        _outSpec = NULL;
        note(ZEIG7Z_IO_ERROR, "can't create file " + unicodeToUtf8(relative));
        return S_OK;
    }
    _out = stream;
    *outStream = stream.Detach();
    return S_OK;
}

Z7_COM7F_IMF(CExtractCallback::PrepareOperation(Int32)) { return S_OK; }

Z7_COM7F_IMF(CExtractCallback::SetOperationResult(Int32 result))
{
    using namespace NArchive::NExtract::NOperationResult;
    const std::string name = unicodeToUtf8(_entryPath);
    switch (result)
    {
        case kOK:
        case kDataAfterEnd:  // trailing junk after a valid stream; the file itself is fine
            break;
        case kUnsupportedMethod:
            note(ZEIG7Z_UNSUPPORTED_METHOD, "unsupported compression method in " + name);
            break;
        case kWrongPassword:
            note(ZEIG7Z_WRONG_PASSWORD, "wrong password for " + name);
            break;
        case kCRCError:
        case kDataError:
            // 7-Zip can't tell a wrong password from damage for most encrypted formats.
            if (_encrypted)
                note(ZEIG7Z_WRONG_PASSWORD, "wrong password, or damaged data, in " + name);
            else
                note(ZEIG7Z_DATA_ERROR, (result == kCRCError ? "checksum error in " : "data error in ") + name);
            break;
        default:
            note(ZEIG7Z_DATA_ERROR, "unreadable data in " + name);
            break;
    }
    if (_outSpec)
    {
        if (_hasMTime)
        {
            CFiTime ft;
            if (FILETIME_To_timespec(_mtime, ft))
                _outSpec->SetMTime(&ft);
        }
        if (_outSpec->Close() != S_OK)
            note(ZEIG7Z_IO_ERROR, "can't finish writing " + name);
        // Keep the stored permission bits, but never lock the user out of their own file.
        if (_hasMode)
            chmod(_outPath.Ptr(), (mode_t)((_mode & 0777) | 0600));
    }
    _out.Release();
    _outSpec = NULL;
    return S_OK;
}

Z7_COM7F_IMF(CExtractCallback::CryptoGetTextPassword(BSTR *result))
{
    if (!hasPassword)
    {
        note(ZEIG7Z_WRONG_PASSWORD, "the archive needs a password");
        return E_ABORT;
    }
    return StringToBstr(password, result);
}

} // namespace

static zeig7z_result runExtract(zeig7z_archive *archive, const char *destination, const uint32_t *indices,
                                uint32_t count, const char *password, const zeig7z_callbacks *callbacks,
                                bool testMode)
{
    CExtractCallback *spec = new CExtractCallback;
    CMyComPtr<IArchiveExtractCallback> callback(spec);
    spec->archive = archive;
    if (destination)
    {
        spec->destination = utf8ToFString(destination);
        if (spec->destination.IsEmpty() || spec->destination.Back() != '/')
            spec->destination += '/';
    }
    spec->hasPassword = password ? true : archive->hasPassword;
    spec->password = password ? utf8ToUnicode(password) : archive->password;
    spec->progress.callbacks = callbacks;

    const HRESULT hr = indices
        ? archive->handler->Extract(indices, count, testMode ? 1 : 0, callback)
        : archive->handler->Extract(NULL, (UInt32)(Int32)-1, testMode ? 1 : 0, callback);

    if (spec->progress.cancelled)
        return fail(ZEIG7Z_CANCELLED, "cancelled");
    if (spec->firstError != ZEIG7Z_OK)
        return fail(spec->firstError, spec->firstErrorMessage);
    if (hr == E_OUTOFMEMORY)
        return fail(ZEIG7Z_OUT_OF_MEMORY, "out of memory");
    if (hr != S_OK)
        return fail(ZEIG7Z_DATA_ERROR, "7-Zip stopped with an error");
    g_lastError.clear();
    return ZEIG7Z_OK;
}

extern "C" zeig7z_result zeig7z_extract(zeig7z_archive *archive, const char *destination,
                                        const uint32_t *indices, uint32_t index_count,
                                        const char *password, const zeig7z_callbacks *callbacks)
{
    if (!archive || !destination)
        return fail(ZEIG7Z_INVALID_ARGUMENT, "archive and destination must not be NULL");
    return runExtract(archive, destination, indices, index_count, password, callbacks, false);
}

extern "C" zeig7z_result zeig7z_test(zeig7z_archive *archive, const char *password,
                                     const zeig7z_callbacks *callbacks)
{
    if (!archive)
        return fail(ZEIG7Z_INVALID_ARGUMENT, "archive must not be NULL");
    return runExtract(archive, NULL, NULL, 0, password, callbacks, true);
}

// MARK: - Creation

namespace {

struct SourceItem
{
    UString nameInArchive;
    FString fullPath;
    struct stat info;
};

/// Adds `path` (named `name` in the archive) and, for folders, everything under it.
/// Symbolic links are left out.
bool collect(const std::string &path, const std::string &name, std::vector<SourceItem> &items, std::string &error)
{
    SourceItem item;
    if (lstat(path.c_str(), &item.info) != 0)
    {
        error = "can't read " + path;
        return false;
    }
    if (S_ISLNK(item.info.st_mode))
        return true;
    item.nameInArchive = utf8ToUnicode(name.c_str());
    item.fullPath = utf8ToFString(path.c_str());
    items.push_back(item);
    if (!S_ISDIR(item.info.st_mode))
        return true;

    DIR *dir = opendir(path.c_str());
    if (!dir)
    {
        error = "can't list " + path;
        return false;
    }
    std::vector<std::string> children;
    while (struct dirent *entry = readdir(dir))
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0)
            children.push_back(entry->d_name);
    closedir(dir);
    std::sort(children.begin(), children.end());
    for (const std::string &child : children)
        if (!collect(path + "/" + child, name + "/" + child, items, error))
            return false;
    return true;
}

class CUpdateCallback Z7_final:
    public IArchiveUpdateCallback2,
    public ICryptoGetTextPassword2,
    public CMyUnknownImp
{
    Z7_IFACES_IMP_UNK_2(IArchiveUpdateCallback2, ICryptoGetTextPassword2)
    Z7_IFACE_COM7_IMP(IProgress)
    Z7_IFACE_COM7_IMP(IArchiveUpdateCallback)

public:
    const std::vector<SourceItem> *items = NULL;
    UString password;
    bool hasPassword = false;
    ProgressRelay progress;
    std::string failedPath;
};

Z7_COM7F_IMF(CUpdateCallback::SetTotal(UInt64 size)) { return progress.setTotal(size); }
Z7_COM7F_IMF(CUpdateCallback::SetCompleted(const UInt64 *value)) { return progress.setCompleted(value); }

Z7_COM7F_IMF(CUpdateCallback::GetUpdateItemInfo(UInt32, Int32 *newData, Int32 *newProperties, UInt32 *indexInArchive))
{
    // Every item is new: Zeig always writes a fresh archive.
    if (newData) *newData = 1;
    if (newProperties) *newProperties = 1;
    if (indexInArchive) *indexInArchive = (UInt32)(Int32)-1;
    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
    NCOM::CPropVariant prop;
    const SourceItem &item = (*items)[index];
    const bool isDir = S_ISDIR(item.info.st_mode);
    switch (propID)
    {
        case kpidIsAnti: prop = false; break;
        case kpidPath: prop = item.nameInArchive; break;
        case kpidIsDir: prop = isDir; break;
        case kpidSize: prop = (UInt64)(isDir ? 0 : item.info.st_size); break;
        case kpidMTime: PropVariant_SetFrom_FiTime(prop, item.info.st_mtimespec); break;
        case kpidCTime: PropVariant_SetFrom_FiTime(prop, item.info.st_birthtimespec); break;
        case kpidATime: PropVariant_SetFrom_FiTime(prop, item.info.st_atimespec); break;
        case kpidPosixAttrib: prop = (UInt32)item.info.st_mode; break;
        case kpidAttrib:
        {
            // Windows attributes with the Unix mode in the high half, as 7-Zip does on Unix.
            UInt32 attrib = FILE_ATTRIBUTE_UNIX_EXTENSION | ((UInt32)item.info.st_mode << 16);
            attrib |= isDir ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_ARCHIVE;
            if ((item.info.st_mode & 0222) == 0)
                attrib |= FILE_ATTRIBUTE_READONLY;
            prop = attrib;
            break;
        }
    }
    prop.Detach(value);
    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::GetStream(UInt32 index, ISequentialInStream **inStream))
{
    *inStream = NULL;
    const SourceItem &item = (*items)[index];
    if (S_ISDIR(item.info.st_mode))
        return S_OK;
    CInFileStream *spec = new CInFileStream;
    CMyComPtr<ISequentialInStream> stream(spec);
    if (!spec->Open(item.fullPath))
    {
        failedPath = item.fullPath.Ptr();
        return E_FAIL;
    }
    *inStream = stream.Detach();
    return S_OK;
}

Z7_COM7F_IMF(CUpdateCallback::SetOperationResult(Int32)) { return S_OK; }

// Volumes (split archives) aren't offered for 7-Zip formats yet.
Z7_COM7F_IMF(CUpdateCallback::GetVolumeSize(UInt32, UInt64 *)) { return S_FALSE; }
Z7_COM7F_IMF(CUpdateCallback::GetVolumeStream(UInt32, ISequentialOutStream **)) { return E_NOTIMPL; }

Z7_COM7F_IMF(CUpdateCallback::CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *result))
{
    *passwordIsDefined = hasPassword ? 1 : 0;
    return StringToBstr(password, result);
}

/// The command line's rule for -m values: digits → number, "" → no value, else text.
void setPropertyValue(NCOM::CPropVariant &prop, const char *value)
{
    if (!value || !*value)
        return;  // VT_EMPTY
    bool digits = true;
    for (const char *p = value; *p; p++)
        digits = digits && *p >= '0' && *p <= '9';
    if (digits && strlen(value) <= 9)
        prop = (UInt32)strtoul(value, NULL, 10);
    else
        prop = utf8ToUnicode(value);
}

} // namespace

extern "C" zeig7z_result zeig7z_create(const char *archivePath, const char *formatName,
                                       const char *const *sources, size_t sourceCount,
                                       const zeig7z_property *properties, size_t propertyCount,
                                       const char *password, const zeig7z_callbacks *callbacks)
{
    if (!archivePath || !formatName || !sources || sourceCount == 0)
        return fail(ZEIG7Z_INVALID_ARGUMENT, "archive path, format and sources are required");
    const Format *format = formatNamed(formatName);
    if (!format)
        return fail(ZEIG7Z_UNSUPPORTED_FORMAT, std::string("7-Zip has no format named ") + formatName);
    if (!format->canWrite)
        return fail(ZEIG7Z_READ_ONLY_FORMAT, "7-Zip can only read " + format->name);

    std::vector<SourceItem> items;
    std::string error;
    for (size_t i = 0; i < sourceCount; i++)
    {
        std::string path(sources[i]);
        while (path.size() > 1 && path.back() == '/')
            path.pop_back();
        const std::string name = path.substr(path.find_last_of('/') + 1);
        if (!collect(path, name, items, error))
            return fail(ZEIG7Z_IO_ERROR, error);
    }
    const bool singleStream = format->name == "gzip" || format->name == "bzip2" || format->name == "xz";
    if (singleStream && (items.size() != 1 || S_ISDIR(items[0].info.st_mode)))
        return fail(ZEIG7Z_INVALID_ARGUMENT, format->name + " holds exactly one file");

    CMyComPtr<IOutArchive> outArchive;
    if (CreateObject(&format->classID, &IID_IOutArchive, (void **)&outArchive) != S_OK || !outArchive)
        return fail(ZEIG7Z_READ_ONLY_FORMAT, "7-Zip can't write " + format->name);

    if (propertyCount > 0)
    {
        CMyComPtr<ISetProperties> setProperties;
        outArchive->QueryInterface(IID_ISetProperties, (void **)&setProperties);
        if (!setProperties)
            return fail(ZEIG7Z_INVALID_ARGUMENT, format->name + " takes no options");
        std::vector<UString> names(propertyCount);
        std::vector<const wchar_t *> namePointers(propertyCount);
        std::vector<NCOM::CPropVariant> values(propertyCount);
        for (size_t i = 0; i < propertyCount; i++)
        {
            names[i] = utf8ToUnicode(properties[i].key);
            namePointers[i] = names[i].Ptr();
            setPropertyValue(values[i], properties[i].value);
        }
        if (setProperties->SetProperties(namePointers.data(), values.data(), (UInt32)propertyCount) != S_OK)
            return fail(ZEIG7Z_INVALID_ARGUMENT, "7-Zip rejected the options for " + format->name);
    }

    const FString outPath = utf8ToFString(archivePath);
    COutFileStream *outSpec = new COutFileStream;
    CMyComPtr<IOutStream> outStream(outSpec);
    if (!outSpec->Create_ALWAYS(outPath))
        return fail(ZEIG7Z_IO_ERROR, "can't create the archive file");

    CUpdateCallback *spec = new CUpdateCallback;
    CMyComPtr<IArchiveUpdateCallback2> callback(spec);
    spec->items = &items;
    spec->hasPassword = password != NULL;
    spec->password = utf8ToUnicode(password);
    spec->progress.callbacks = callbacks;

    const HRESULT hr = outArchive->UpdateItems(outStream, (UInt32)items.size(), callback);
    const HRESULT closed = outSpec->Close();
    if (hr != S_OK || closed != S_OK)
    {
        unlink(archivePath);
        if (spec->progress.cancelled)
            return fail(ZEIG7Z_CANCELLED, "cancelled");
        if (!spec->failedPath.empty())
            return fail(ZEIG7Z_IO_ERROR, "can't read " + spec->failedPath);
        if (hr == E_OUTOFMEMORY)
            return fail(ZEIG7Z_OUT_OF_MEMORY, "out of memory");
        if (hr == E_INVALIDARG)
            return fail(ZEIG7Z_INVALID_ARGUMENT, "7-Zip rejected the options for " + format->name);
        return fail(closed != S_OK ? ZEIG7Z_IO_ERROR : ZEIG7Z_UNKNOWN_ERROR, "7-Zip couldn't write the archive");
    }
    g_lastError.clear();
    return ZEIG7Z_OK;
}
