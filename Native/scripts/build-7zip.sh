#!/usr/bin/env bash
# Builds CSevenZip.xcframework: all of 7-Zip's format handlers and codecs (the same set as
# its 7z.so, "Format7zF") plus Zeig's C bridge (Native/zeig7z), as one static library per
# slice.
#
#   Native/scripts/build-7zip.sh
#
# Why it's linked the unusual way: each 7-Zip format handler registers itself from a static
# initializer, and nothing references the handler's object file directly. Put them in a
# normal static library and the linker would drop every handler. So all objects are first
# combined into a single relocatable object (`clang -r`), exporting only the zeig7z_*
# functions. Pulling in any zeig7z_* symbol then pulls in everything, and 7-Zip's internal
# names (CRC tables, LZMA functions…) stay private, so they can't clash with libarchive's
# copies of the same algorithms.
#
# See docs/native-builds.md.

source "$(dirname "$0")/common.sh"

SEVENZIP="$VENDOR/7zip"
BRIDGE="$ROOT/Native/zeig7z"
# Same defines 7-Zip's makefile uses, so the bridge sees the same struct layouts.
DEFINES="-DNDEBUG -D_REENTRANT -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DZ7_EXTERNAL_CODECS"

for slice in "${SLICES[@]}"; do
    sysroot="$(xcrun --sdk "$(sdk_for "$slice")" --show-sdk-path)"
    arch="-target $(target_for "$slice") -isysroot $sysroot"
    objects="$BUILD/$slice/7zip-obj"
    out="$BUILD/$slice/CSevenZip"
    rm -rf "$objects" "$out" && mkdir -p "$objects" "$out/lib"

    log "$slice: 7-Zip handlers"
    # USE_ASM is off: the hand-written ARM64 assembly is only a small speed-up for LZMA
    # decoding, and the C versions build everywhere. The final link of 7z.so fails for iOS
    # targets and isn't needed (-k keeps going); only the object files are used.
    (cd "$SEVENZIP/CPP/7zip/Bundles/Format7zF" && make -k -f makefile.gcc -j"$JOBS" \
        O="$objects" CC="clang" CXX="clang++" MY_ARCH="$arch" \
        IS_ARM64=1 USE_ASM= CFLAGS_WARN="-w" CFLAGS_WARN_WALL= \
        >"$objects.log" 2>&1) || true
    count="$(ls "$objects"/*.o 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count" -lt 200 ]; then
        echo "7-Zip compile failed ($count objects); see $objects.log" >&2
        grep -m 20 -E 'error' "$objects.log" >&2 || tail -30 "$objects.log" >&2
        exit 1
    fi

    log "$slice: bridge"
    clang++ $arch -std=c++17 -O2 -fPIC -w $DEFINES \
        -I"$SEVENZIP/CPP" -I"$BRIDGE/include" \
        -c "$BRIDGE/src/zeig7z.cpp" -o "$out/zeig7z.o"
    # File streams aren't part of the format bundle (7z.so gets them from its host).
    clang++ $arch -O2 -fPIC -w $DEFINES \
        -c "$SEVENZIP/CPP/7zip/Common/FileStreams.cpp" -o "$out/FileStreams.o"

    log "$slice: link"
    echo "_zeig7z_*" >"$out/exports.txt"
    clang++ $arch -r -nostdlib -Wl,-exported_symbols_list,"$out/exports.txt" \
        -o "$out/CSevenZip.o" "$objects"/*.o "$out/FileStreams.o" "$out/zeig7z.o"
    libtool -static -no_warning_for_no_symbols -o "$out/lib/libCSevenZip.a" "$out/CSevenZip.o"
done

headers="$BUILD/CSevenZip-headers"
rm -rf "$headers" && mkdir -p "$headers"
cp "$BRIDGE/include/zeig7z.h" "$headers/"
cat >"$headers/module.modulemap" <<'EOF'
module CSevenZip {
    header "zeig7z.h"
    link "c++"
    export *
}
EOF

make_xcframework CSevenZip "$headers" libCSevenZip.a
