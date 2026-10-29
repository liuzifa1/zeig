#!/usr/bin/env bash
# Builds all three native libraries into Packages/ZeigKit/Frameworks. Run once after cloning
# (after `git submodule update --init`), and again after changing anything under Native/.
#
#   Native/scripts/build-all.sh
#
# First run: about 15 minutes (Rust's release build with LTO is most of it). Later runs reuse
# ~/Library/Caches/Zeig/native and take a few minutes. See docs/native-builds.md.

set -euo pipefail
cd "$(dirname "$0")"

missing=()
for tool in cmake cargo rustup xcodebuild; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing: ${missing[*]}. See docs/native-builds.md → Prerequisites." >&2
    exit 1
fi
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    rustup target list --installed | grep -qx "$target" || {
        echo "Missing Rust target $target: rustup target add $target" >&2
        exit 1
    }
done
if [ ! -f ../vendor/7zip/C/7zVersion.h ]; then
    echo "Native sources missing: git submodule update --init" >&2
    exit 1
fi

./build-libarchive.sh
./build-7zip.sh
./build-rars.sh
echo "All native libraries built."
