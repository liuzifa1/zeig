#!/usr/bin/env bash
# Builds CLibArchive.xcframework: libarchive plus the compression libraries the iOS SDK
# doesn't provide (xz/liblzma, zstd, lz4), merged into one static library per slice.
#
# zlib, bzip2, iconv and libxml2 (for xar) come from the SDK; the module map links them.
# Encryption (zip AES, 7z AES) uses CommonCrypto, also from the SDK, so no OpenSSL.
#
#   Native/scripts/build-libarchive.sh
#
# See docs/native-builds.md for what each step does and how to update a library.

source "$(dirname "$0")/common.sh"

for slice in "${SLICES[@]}"; do
    log "$slice: xz"
    cmake_install "$slice" "$VENDOR/xz" xz \
        -DBUILD_TESTING=OFF -DXZ_NLS=OFF -DXZ_DOC=OFF \
        -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF \
        -DXZ_TOOL_SCRIPTS=OFF

    log "$slice: zstd"
    cmake_install "$slice" "$VENDOR/zstd/build/cmake" zstd \
        -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
        -DZSTD_BUILD_TESTS=OFF -DZSTD_MULTITHREAD_SUPPORT=ON

    log "$slice: lz4"
    cmake_install "$slice" "$VENDOR/lz4/build/cmake" lz4 \
        -DLZ4_BUILD_CLI=OFF -DLZ4_BUILD_LEGACY_LZ4C=OFF -DBUILD_STATIC_LIBS=ON

    deps="$BUILD/$slice"
    log "$slice: libarchive"
    # Only the library: no bsdtar/bsdcpio tools, no tests. The crypto backends other than
    # CommonCrypto are switched off so CMake can't pick up a Homebrew OpenSSL for the Mac slice.
    cmake_install "$slice" "$VENDOR/libarchive" libarchive \
        -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF -DENABLE_TEST=OFF \
        -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF -DENABLE_NETTLE=OFF -DENABLE_CNG=OFF \
        -DENABLE_LIBB2=OFF -DENABLE_LZO=OFF -DENABLE_PCREPOSIX=OFF -DENABLE_PCRE2POSIX=OFF \
        -DENABLE_EXPAT=OFF -DENABLE_LIBXML2=ON -DENABLE_ICONV=ON \
        -DENABLE_ACL=OFF -DENABLE_XATTR=ON \
        -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_LZMA=ON -DENABLE_ZSTD=ON -DENABLE_LZ4=ON \
        -DLIBLZMA_INCLUDE_DIR="$deps/xz/include" -DLIBLZMA_LIBRARY="$deps/xz/lib/liblzma.a" \
        -DZSTD_INCLUDE_DIR="$deps/zstd/include" -DZSTD_LIBRARY="$deps/zstd/lib/libzstd.a" \
        -DLZ4_INCLUDE_DIR="$deps/lz4/include" -DLZ4_LIBRARY="$deps/lz4/lib/liblz4.a"

    # One static library per slice, so the app links a single binary target.
    out="$BUILD/$slice/CLibArchive/lib"
    mkdir -p "$out"
    libtool -static -no_warning_for_no_symbols -o "$out/libCLibArchive.a" \
        "$deps/libarchive/lib/libarchive.a" "$deps/xz/lib/liblzma.a" \
        "$deps/zstd/lib/libzstd.a" "$deps/lz4/lib/liblz4.a"
done

# Headers + module map. The `link` lines make Swift link the SDK libraries automatically.
headers="$BUILD/CLibArchive-headers"
rm -rf "$headers" && mkdir -p "$headers"
cp "$BUILD/ios/libarchive/include/archive.h" "$BUILD/ios/libarchive/include/archive_entry.h" "$headers/"
cat >"$headers/module.modulemap" <<'EOF'
module CLibArchive {
    header "archive.h"
    header "archive_entry.h"
    link "z"
    link "bz2"
    link "iconv"
    link "xml2"
    export *
}
EOF

make_xcframework CLibArchive "$headers" libCLibArchive.a
