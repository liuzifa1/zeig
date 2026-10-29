#!/usr/bin/env bash
# Shared settings for the native build scripts. Sourced, never run directly.
#
# Every script builds the same three slices:
#   ios        arm64, iPhoneOS SDK           (devices)
#   iossim     arm64, iPhoneSimulator SDK    (Apple-silicon simulators)
#   macos      arm64, macOS SDK              (only so `swift test` runs on the Mac)
# and packages them as an .xcframework in Packages/ZeigKit/Frameworks, where Package.swift
# picks it up as a binary target. Intel simulators are not built.
#
# Intermediate files go to $ZEIG_NATIVE_BUILD (default ~/Library/Caches/Zeig/native), outside
# the repo: the repo lives in an iCloud-synced folder, and object files don't belong there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR="$ROOT/Native/vendor"
FRAMEWORKS="$ROOT/Packages/ZeigKit/Frameworks"
BUILD="${ZEIG_NATIVE_BUILD:-$HOME/Library/Caches/Zeig/native}"

IOS_MIN=18.0
MACOS_MIN=15.0
SLICES=(ios iossim macos)
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$BUILD" "$FRAMEWORKS"

# sdk_for <slice>: the xcrun SDK name.
sdk_for() {
    case "$1" in
        ios) echo iphoneos ;;
        iossim) echo iphonesimulator ;;
        macos) echo macosx ;;
        *) echo "unknown slice $1" >&2; return 1 ;;
    esac
}

# target_for <slice>: the clang target triple (sets the minimum OS too).
target_for() {
    case "$1" in
        ios) echo "arm64-apple-ios$IOS_MIN" ;;
        iossim) echo "arm64-apple-ios$IOS_MIN-simulator" ;;
        macos) echo "arm64-apple-macos$MACOS_MIN" ;;
    esac
}

# cmake_install <slice> <source dir> <name> [extra -D args…]: configures, builds and installs a
# CMake project as a static library into $BUILD/<slice>/<name>. (macOS ships bash 3.2, so this
# takes the platform flags itself instead of returning an array.)
cmake_install() {
    local slice="$1" src="$2" name="$3"
    shift 3
    local prefix="$BUILD/$slice/$name" work="$BUILD/$slice/$name-build"
    local sysroot
    sysroot="$(xcrun --sdk "$(sdk_for "$slice")" --show-sdk-path)"
    local platform=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN")
    if [ "$slice" != macos ]; then
        platform=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN")
    fi
    rm -rf "$work" "$prefix"
    mkdir -p "$BUILD/$slice"
    cmake -S "$src" -B "$work" -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        "${platform[@]}" "$@" >"$work.log" 2>&1 \
        || { tail -40 "$work.log"; return 1; }
    cmake --build "$work" --parallel "$JOBS" >>"$work.log" 2>&1 \
        && cmake --install "$work" >>"$work.log" 2>&1 \
        || { tail -40 "$work.log"; return 1; }
}

# make_xcframework <name> <headers dir> <lib name>: bundles $BUILD/<slice>/<name>/lib/<lib name>
# for every slice into $FRAMEWORKS/<name>.xcframework, with <headers dir> as its headers.
#
# The headers go one folder down, in Headers/<name>/. SwiftPM copies the headers of every
# static-library framework into one shared include/ folder, so three module.modulemap files
# side by side would overwrite each other; in a folder named after the module, Clang still
# finds each one when Swift says `import <name>`.
make_xcframework() {
    local name="$1" headers="$2" lib="$3"
    local wrapped="$BUILD/$name-headers-wrapped"
    rm -rf "$wrapped" && mkdir -p "$wrapped/$name"
    cp -R "$headers"/. "$wrapped/$name/"
    local args=()
    for slice in "${SLICES[@]}"; do
        args+=(-library "$BUILD/$slice/$name/lib/$lib" -headers "$wrapped")
    done
    rm -rf "$FRAMEWORKS/$name.xcframework"
    xcodebuild -create-xcframework "${args[@]}" -output "$FRAMEWORKS/$name.xcframework" >/dev/null
    echo "→ $FRAMEWORKS/$name.xcframework"
}

log() { printf '\033[1m== %s\033[0m\n' "$*"; }
