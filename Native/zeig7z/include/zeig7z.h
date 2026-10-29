/*
 * zeig7z.h — Zeig's C interface to 7-Zip.
 *
 * 7-Zip's own API is C++ with Windows-style COM interfaces (IInArchive, IOutArchive,
 * callback objects, PROPVARIANTs, BSTR strings). Swift can't call that directly, so this
 * header wraps the handful of operations Zeig needs in plain C: list the formats, open an
 * archive, read its entries, extract or test it, and create a new one. Swift imports it as
 * the `CSevenZip` module (see module.modulemap next to this file).
 *
 * The implementation (src/zeig7z.cpp) is adapted from 7-Zip's Client7z sample, and is
 * licensed like 7-Zip itself: GNU LGPL 2.1 or later. See Native/zeig7z/README.md.
 *
 * Conventions
 * -----------
 * - Strings are UTF-8, NUL-terminated. Paths are absolute file-system paths.
 * - Every function that can fail returns a `zeig7z_result`. On failure,
 *   `zeig7z_last_error()` gives a human-readable English detail for the calling thread
 *   (valid until the next zeig7z call on that thread).
 * - Strings returned by the library are owned by it. Their lifetime is stated on each
 *   function; copy them if you need them longer.
 * - An archive handle is not thread-safe: use one handle from one thread at a time.
 *   Different handles may be used from different threads at once.
 * - Calls block until done. Run them off the main thread; cancel through the progress
 *   callback.
 */

#ifndef ZEIG7Z_H
#define ZEIG7Z_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* MARK: - Results */

typedef enum zeig7z_result {
    ZEIG7Z_OK = 0,
    /** No 7-Zip handler can open this file, or the named format doesn't exist. */
    ZEIG7Z_UNSUPPORTED_FORMAT = 1,
    /** The file looks like the format but its headers are broken. */
    ZEIG7Z_CORRUPT_ARCHIVE = 2,
    /** A password is needed and none was given, or the given one is wrong. */
    ZEIG7Z_WRONG_PASSWORD = 3,
    /** Data failed its checksum, or ended early, while extracting or testing. */
    ZEIG7Z_DATA_ERROR = 4,
    /** The archive uses a compression method this build doesn't include. */
    ZEIG7Z_UNSUPPORTED_METHOD = 5,
    /** Reading or writing a file on disk failed (permissions, disk full, missing file). */
    ZEIG7Z_IO_ERROR = 6,
    /** The progress callback asked to stop. Partial output may be left on disk. */
    ZEIG7Z_CANCELLED = 7,
    /** An argument was NULL or out of range, or a property was rejected by the format. */
    ZEIG7Z_INVALID_ARGUMENT = 8,
    /** The format can be read but not written by 7-Zip. */
    ZEIG7Z_READ_ONLY_FORMAT = 9,
    ZEIG7Z_OUT_OF_MEMORY = 10,
    /** Anything else; see zeig7z_last_error(). */
    ZEIG7Z_UNKNOWN_ERROR = 99
} zeig7z_result;

/** English detail for the last failure on this thread, or "" if none. */
const char *zeig7z_last_error(void);

/* MARK: - Library info */

/** 7-Zip's version string, such as "26.05". Static; never freed. */
const char *zeig7z_version(void);

/** One format handler compiled into this build. */
typedef struct zeig7z_format_info {
    /** 7-Zip's handler name, such as "7z", "zip", "Rar5", "Iso". Pass it to zeig7z_open
     *  or zeig7z_create. */
    const char *name;
    /** Space-separated extensions without dots, such as "7z" or "tar tgz tbz2". May be "". */
    const char *extensions;
    /** 1 if 7-Zip can create archives in this format, 0 if it can only read them. */
    int can_write;
} zeig7z_format_info;

/** Number of format handlers. */
uint32_t zeig7z_format_count(void);

/** Fills `out` for the handler at `index` (0 ..< zeig7z_format_count()). The strings live
 *  as long as the process. */
zeig7z_result zeig7z_format_at(uint32_t index, zeig7z_format_info *out);

/* MARK: - Callbacks */

/**
 * Optional hooks for a long operation. Any member may be NULL.
 *
 * `progress` is called from the thread running the operation with bytes done and the
 * expected total (total may be 0 when unknown). Return non-zero to cancel; the operation
 * then fails with ZEIG7Z_CANCELLED.
 */
typedef struct zeig7z_callbacks {
    void *context;
    int (*progress)(void *context, uint64_t completed, uint64_t total);
} zeig7z_callbacks;

/* MARK: - Reading */

/** An open archive. Create with zeig7z_open, free with zeig7z_close. */
typedef struct zeig7z_archive zeig7z_archive;

/**
 * Opens the archive at `path`.
 *
 * `formats` is a comma-separated list of handler names to try in order, such as
 * "Rar5,Rar", or NULL to detect the format from the file's signature. Split archives
 * (name.7z.001, name.part1.rar) open from their first volume; the other volumes are found
 * next to it.
 *
 * `password` (UTF-8, may be NULL) is used for archives with encrypted headers (7z with
 * "encrypt file names", RAR with -hp) and kept for extracting encrypted entries later.
 * Opening such an archive without one fails with ZEIG7Z_WRONG_PASSWORD.
 *
 * On success `*out` owns the open file until zeig7z_close.
 */
zeig7z_result zeig7z_open(const char *path, const char *formats, const char *password,
                          zeig7z_archive **out);

/** Closes the archive and frees the handle. NULL is ignored. */
void zeig7z_close(zeig7z_archive *archive);

/** The handler that opened the archive, such as "7z". Valid until zeig7z_close. */
const char *zeig7z_archive_format(const zeig7z_archive *archive);

/** What 7-Zip knows about the archive as a whole. */
typedef struct zeig7z_archive_info {
    /** Compression method(s) for the archive, such as "LZMA2:24 BCJ", or "" if unknown. For
     *  formats that only record methods per entry, the largest file's. */
    const char *method;
    /** 1 solid, 0 not solid, -1 unknown. */
    int solid;
    /** Bytes the archive occupies on disk across all volumes, or 0 if unknown. */
    uint64_t physical_size;
    /** Number of volumes, or 0 if unknown. */
    uint32_t volume_count;
    /** The archive comment, or "". */
    const char *comment;
} zeig7z_archive_info;

/** Fills `out`. The strings are valid until zeig7z_close. */
zeig7z_result zeig7z_get_archive_info(zeig7z_archive *archive, zeig7z_archive_info *out);

/** Number of entries (files and folders). */
uint32_t zeig7z_entry_count(const zeig7z_archive *archive);

/** Metadata for one entry. */
typedef struct zeig7z_entry {
    /** Path inside the archive with '/' separators, as stored (not sanitized). Valid until
     *  the next zeig7z_entry_at call on the same archive, or zeig7z_close. */
    const char *path;
    uint64_t size;
    /** Compressed size, or 0 when the format doesn't record it per entry. */
    uint64_t packed_size;
    /** Modification time in seconds since 1970, and whether the archive stores one. */
    int64_t modified;
    int has_modified;
    int is_directory;
    int is_encrypted;
    /** Unix symbolic link. Zeig doesn't recreate links when extracting; it skips them. */
    int is_symlink;
} zeig7z_entry;

zeig7z_result zeig7z_entry_at(zeig7z_archive *archive, uint32_t index, zeig7z_entry *out);

/**
 * Extracts entries into the existing directory `destination`.
 *
 * `indices` lists the entries to extract (sorted ascending); pass NULL and 0 for all.
 * Paths are made safe first: leading '/', '.' and '..' components are dropped, so nothing
 * is written outside `destination`. Existing files with the same name are replaced.
 * Symbolic links are skipped.
 *
 * `password` (may be NULL) overrides the one given to zeig7z_open.
 */
zeig7z_result zeig7z_extract(zeig7z_archive *archive, const char *destination,
                             const uint32_t *indices, uint32_t index_count,
                             const char *password, const zeig7z_callbacks *callbacks);

/** Decompresses every entry and checks it without writing anything. ZEIG7Z_OK means the
 *  whole archive is intact. */
zeig7z_result zeig7z_test(zeig7z_archive *archive, const char *password,
                          const zeig7z_callbacks *callbacks);

/* MARK: - Writing */

/**
 * A compression setting, in the syntax of 7-Zip's command-line -m switch without "-m":
 * {"x", "9"} is -mx=9 (level), {"m", "LZMA2"} the method, {"s", "off"} no solid block,
 * {"he", "on"} encrypt 7z headers, {"em", "AES256"} zip encryption, {"d", "64m"} the
 * dictionary, {"mt", "4"} threads. A value made only of digits is passed as a number, ""
 * as "no value", anything else as text, as the command line does. Which keys a format
 * accepts is listed in 7-Zip's DOC/Methods.txt.
 */
typedef struct zeig7z_property {
    const char *key;
    const char *value;
} zeig7z_property;

/**
 * Creates a new archive at `archive_path` (replacing any file there) in the handler
 * `format` (a name with can_write == 1).
 *
 * Each of `sources` is a file or folder; folders are added recursively. Entries are named
 * relative to their source's parent, so "/a/b/photos" becomes "photos/…" in the archive.
 * Single-stream formats (gzip, bzip2, xz) take exactly one file.
 *
 * `password` (may be NULL) encrypts the entries; for 7z, add {"he", "on"} to hide the
 * file names too. If creation fails, the partial archive is deleted.
 */
zeig7z_result zeig7z_create(const char *archive_path, const char *format,
                            const char *const *sources, size_t source_count,
                            const zeig7z_property *properties, size_t property_count,
                            const char *password, const zeig7z_callbacks *callbacks);

#ifdef __cplusplus
}
#endif

#endif /* ZEIG7Z_H */
