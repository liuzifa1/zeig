#!/usr/bin/env bash
# Makes the RAR test archives for ZeigBackendsTests with RARLAB's own `rar` and `unrar`, so
# Zeig's RAR readers (7-Zip, and the experimental rars) are tested against the real thing.
#
#   1. Put a few test files in   Native/fixtures/rar-input/
#      (any mix: text, a photo, a subfolder, a non-English file name, an empty folder…).
#      Keep it small, a few MB at most: every archive below is checked into git.
#   2. Optional: drop ready-made .rar files (RAR4 from an old WinRAR, multi-volume sets,
#      files from the internet you have the right to use) into  Native/fixtures/rar-extra/
#   3. Run  Native/scripts/make-rar-fixtures.sh
#   4. Run the tests:  swift test --package-path Packages/ZeigKit --scratch-path "$TMPDIR/zeigkit-build"
#
# The script writes the archives plus manifest.json: for every archive, the password (if
# any) and the SHA-256 of every file it must extract to. For your own files the expected
# contents come from rar-input/; for rar-extra/ files they come from extracting with unrar.
#
# Needs `rar` and `unrar` (brew install rar). rar 7 can't create RAR4 archives any more;
# put RAR4 files in rar-extra/ to cover that format.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="$ROOT/Packages/ZeigKit/Tests/ZeigBackendsTests/Fixtures/RAR"
INPUT="$ROOT/Native/fixtures/rar-input"
EXTRA="$ROOT/Native/fixtures/rar-extra"
OUT="$FIXTURES/archives"
PASSWORD="zeig-fixture"

command -v rar >/dev/null || { echo "rar not found: brew install rar" >&2; exit 1; }
command -v unrar >/dev/null || { echo "unrar not found: brew install rar" >&2; exit 1; }
mkdir -p "$INPUT" "$EXTRA"
if [ -z "$(ls -A "$INPUT")" ]; then
    echo "Put some test files in $INPUT first (see the top of this script)." >&2
    exit 1
fi

rm -rf "$OUT" && mkdir -p "$OUT"
log="$OUT/rar.fixture-log"
input_bytes=$(du -sk "$INPUT" | cut -f1)
# Volumes: about three parts, never below 64 KB.
volume_kb=$(( input_bytes / 3 > 64 ? input_bytes / 3 : 64 ))

# make <name> <rar switches…>: archives everything in rar-input/ (names relative to it).
make() {
    local name="$1"
    shift
    echo "  $name"
    (cd "$INPUT" && rar a -r -idq -y "$@" "$OUT/$name" . >>"$log" 2>&1)
}

echo "Creating archives with $(rar 2>&1 | grep -m1 "^RAR" | sed "s/   *.*//" || true)"
make rar5-normal.rar -ma5 -m3
make rar5-store.rar -ma5 -m0
make rar5-best.rar -ma5 -m5
make rar5-solid.rar -ma5 -m3 -s
make rar5-password.rar -ma5 -m3 "-p$PASSWORD"
make rar5-encrypted-names.rar -ma5 -m3 "-hp$PASSWORD"
make rar5-recovery.rar -ma5 -m3 -rr5%
make rar5-volumes.rar -ma5 -m0 "-v${volume_kb}k"

for file in "$EXTRA"/*.rar; do
    [ -e "$file" ] || continue
    echo "  extra/$(basename "$file")"
    cp "$file" "$OUT/extra-$(basename "$file")"
done

echo "Writing manifest.json"
python3 -I - "$INPUT" "$OUT" "$PASSWORD" <<'PY'
import hashlib, json, os, subprocess, sys, tempfile

input_dir, out_dir, password = sys.argv[1:4]

def tree(root):
    files, folders = {}, []
    for folder, dirs, names in os.walk(root):
        rel = os.path.relpath(folder, root)
        if rel != "." and not dirs and not names:
            folders.append(rel)
        for name in names:
            path = os.path.join(folder, name)
            with open(path, "rb") as f:
                files[os.path.relpath(path, root)] = hashlib.sha256(f.read()).hexdigest()
    return files, sorted(folders)

own_files, own_empty = tree(input_dir)
archives = []
for name in sorted(os.listdir(out_dir)):
    if not name.endswith(".rar"):
        continue
    # Only the first part of a volume set is opened; the rest are found from it.
    if ".part" in name and not name.split(".part")[1].lstrip("0").startswith("1."):
        continue
    secret = password if "password" in name or "encrypted" in name else None
    if name.startswith("extra-"):
        with tempfile.TemporaryDirectory() as scratch:
            # unrar is the reference: what it extracts is what Zeig must extract.
            args = ["unrar", "x", "-idq", "-y", "-p-", os.path.join(out_dir, name), scratch + "/"]
            if subprocess.run(args).returncode != 0:
                print(f"  skipping {name}: unrar can't extract it (needs a password?)")
                continue
            files, empty = tree(scratch)
    else:
        files, empty = own_files, own_empty
    archives.append({"file": name, "password": secret, "files": files, "emptyFolders": empty})

with open(os.path.join(out_dir, "manifest.json"), "w") as f:
    json.dump({"archives": archives}, f, indent=2, sort_keys=True, ensure_ascii=False)
print(f"  {len(archives)} archives")
PY
rm -f "$log"
echo "Done. Commit $OUT (rar-input/ and rar-extra/ stay out of git)."
