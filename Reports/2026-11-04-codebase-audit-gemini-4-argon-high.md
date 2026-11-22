# Zeig! Codebase Audit Report — Vulnerabilities, Bugs & Performance

- **Date:** 2026-11-04
- **Model:** Gemini 4 Argon (High)
- **Repository:** `Zeig!` (`top.kitsune.zeig`)
- **Scope:** Full-stack static audit of `App/`, `Packages/ZeigKit/` (`ZeigCore`, `ZeigBackends`, `ZeigStore`, `ZeigDesign`, `ArchiveFeature`, `BrowseFeature`, `RecentFeature`, `SearchFeature`, `SettingsFeature`), `Native/zeig7z/` (C/C++), `Native/rars-ffi/` (Rust/UniFFI), and `Native/scripts/`.

---

## Executive Summary

Zeig! has a remarkably clean, well-factored Swift 6 architecture with strict concurrency (`@MainActor` stores/view-models, detached background execution for blocking native backends), typed `ArchiveError` propagation, and existing test coverage for basic path traversal ("zip slip"), passwords, and cross-backend round trips.

However, a deep line-by-line audit across the Swift, C++, and Rust layers uncovered **19 actionable findings**:
- **6 Security & Hardening Issues** (including a **High** severity Swift `UInt64` integer overflow crash triggered simply by opening an archive with crafted header sizes, unbounded sparse-file offset writes in `LibArchiveBackend`, non-regular file extraction edge cases, and missing resource quotas on Quick Look previews).
- **8 Functional Bugs** (including silent overwrites and leftover parts when creating split RAR archives, dropped empty folders during partial RAR extraction, `RecentStore` & `FolderModel` path desynchronization on folder rename/move/delete, concurrent `ArchiveActions` state corruption when extracting multiple archives, and un-cancellable `rars` test/verification passes).
- **5 Performance & Scalability Issues** (including $O(N \cdot D)$ memory amplification and main-thread tree construction in `ArchiveTree`, main-thread recursive filesystem enumeration in `SearchView`, redundant disk `stat` calls during `RecentView` rendering, and an all-at-once eviction cliff in `ThumbnailCache`).

---

## 1. Security Vulnerabilities & Hardening

### [SEC-01] High — Integer Overflow Crash (`EXC_BREAKPOINT`) When Opening Archives with Crafted Entry Sizes
- **Locations:**
  - `Packages/ZeigKit/Sources/ZeigCore/ArchiveTree.swift:35` (`ArchiveTree.init`)
  - `Packages/ZeigKit/Sources/ArchiveFeature/ArchiveView.swift:37` (`ArchiveModel.summary`)
  - `Packages/ZeigKit/Sources/ZeigCore/Backend.swift:164` (`ArchiveStatistics.init`)
  - `Packages/ZeigKit/Sources/ArchiveFeature/FolderModel.swift:204` (`FolderModel.summary`)
  - `Packages/ZeigKit/Sources/ZeigBackends/LibArchiveBackend.swift:220, 370` (`createArchive`, `writeItem`)
  - `Native/rars-ffi/src/lib.rs:306` (`run_extraction`)
- **Vulnerability & Mechanics:**
  In Swift, standard `+` and `+=` operators on `UInt64` trap at runtime on overflow. When an archive is opened (listed) in `ArchiveView`, before any extraction takes place:
  1. `ArchiveTree.init(entries:)` accumulates folder sizes from header metadata:
     ```swift
     folders[ancestor, default: (0, nil)].size += entry.isDirectory ? 0 : entry.size
     ```
  2. `ArchiveModel.summary` and `ArchiveStatistics.init` sum all file entry sizes:
     ```swift
     let size = files.reduce(UInt64(0)) { $0 + $1.size }
     ```
  3. In Rust (`Native/rars-ffi/src/lib.rs:306`), `members.iter().map(|m| m.meta.unpacked_size).sum()` also sums untrusted 64-bit `unpacked_size` header fields.
- **Impact:**
  A tiny (few-hundred-byte) archive containing two or more entries whose header `uncompressed_size` fields sum to $> 2^{64} - 1$ immediately crashes the app upon tapping the archive in Browse, Recent, or "Open in Zeig".
- **Recommendation:**
  Use saturating addition (`addingReportingOverflow`) in Swift:
  ```swift
  extension UInt64 {
      func saturatingAdd(_ other: UInt64) -> UInt64 {
          let (partial, overflow) = addingReportingOverflow(other)
          return overflow ? .max : partial
      }
  }
  ```
  And in `Native/rars-ffi/src/lib.rs:306`, use `.fold(0u64, u64::saturating_add)` instead of `.sum()`.

---

### [SEC-02] Medium — Unvalidated Sparse File Offset in `LibArchiveBackend.writeData` ("Sparse File Bomb") and Partial `pwrite` Handling
- **Location:** `Packages/ZeigKit/Sources/ZeigBackends/LibArchiveBackend.swift:166-174`
- **Vulnerability & Mechanics:**
  ```swift
  let status = archive_read_data_block(reader, &block, &size, &offset)
  if status == ARCHIVE_EOF { return }
  guard status == ARCHIVE_OK || status == ARCHIVE_WARN else { throw dataError(reader) }
  if let block, size > 0, pwrite(fd, block, size, off_t(offset)) != size {
      throw .io(detail: "can't write \(target.lastPathComponent)")
  }
  ```
  1. `offset` (`la_int64_t`) comes directly from archive entry headers (such as GNU/PAX sparse tar headers). If `offset < 0` or `offset` is set to an extreme value (e.g., multiple terabytes with a 1-byte payload), `pwrite` seeks to `off_t(offset)` without validating against a reasonable bound or negative offset. If a user later duplicates, shares, or compresses that extracted sparse file, reading it back expands the sparse holes into gigabytes/terabytes of zeroes, exhausting memory or disk space.
  2. Additionally, POSIX `pwrite` can legitimately write fewer than `size` bytes on `EINTR` or large buffers; checking `pwrite(...) != size` without a write loop can fail spuriously.
- **Recommendation:**
  Validate that `offset >= 0`, track total logical file extent (`offset + size`), and loop on partial `pwrite` calls (retrying on `EINTR`).

---

### [SEC-03] Medium — Non-Regular Files (Hardlinks, FIFOs, Device Nodes) Treated as Regular Files in `LibArchiveBackend`
- **Location:** `Packages/ZeigKit/Sources/ZeigBackends/LibArchiveBackend.swift:74-84, 140-155`
- **Vulnerability & Mechanics:**
  `makeEntry` only checks for directories (`FileType.directory` = `0o040000`) and symlinks (`FileType.symlink` = `0o120000`):
  ```swift
  let type = UInt32(archive_entry_filetype(entry))
  ...
  isDirectory: type == FileType.directory || path.hasSuffix("/"),
  isEncrypted: archive_entry_is_encrypted(entry) != 0,
  isSymlink: type == FileType.symlink
  ```
  In `tar`, `cpio`, `iso`, and `xar` archives:
  1. **Hardlink entries** often have `archive_entry_hardlink(entry) != nil` and `size == 0` (no data payload). If an archive contains a regular file `a.txt` followed by a hardlink entry pointing back to `a.txt` (or sharing a sanitized path), `extractEntries` treats it as a regular file, calls `unlink(target.path)` and `O_TRUNC` in `writeData`, and clobbers the extracted file with a 0-byte file.
  2. **Special file types** (`AE_IFIFO`, `AE_IFCHR`, `AE_IFBLK`, `AE_IFSOCK`) are not filtered out, so `extractEntries` creates empty regular files for them.
- **Recommendation:**
  In `LibArchiveBackend`, skip any entry where `archive_entry_hardlink(entry) != nil` or where `type != FileType.regular && type != FileType.directory` (just as symlinks are skipped).

---

### [SEC-04] Medium — Intermediate Parent Directory Symlink Traversal During Extraction into Existing Directories
- **Locations:**
  - `Native/zeig7z/src/zeig7z.cpp:730-750` (`CExtractCallback::GetStream`)
  - `Packages/ZeigKit/Sources/ZeigBackends/LibArchiveBackend.swift:76-83` (`extractEntries`)
  - `Native/rars-ffi/src/lib.rs:315-326` (`run_extraction`)
- **Vulnerability & Mechanics:**
  All three backends sanitize `..` and leading `/` components from entry paths, skip symlink entries inside the archive, and `unlink` the leaf target file before opening it. However, `CreateComplexDir` / `FileManager.createDirectory(withIntermediateDirectories: true)` / `fs::create_dir_all` will follow an **already-existing directory symlink** inside `destination`.
  While `ArchiveService.extractToNewFolder` creates a fresh directory via `FileNaming.unique`, `ArchiveService.extract(_:entries:to:password:progress:)` is a public API accepting any `destination: URL`, and the app's `Documents` directory is exposed to external modification via `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.
- **Recommendation:**
  Verify that resolved parent directories remain inside `destination.resolvingSymlinksInPath()` (or walk path components with `openat(..., O_NOFOLLOW | O_DIRECTORY)`) before writing leaf files.

---

### [SEC-05] Medium — Unbounded Decompression & Un-cancellable Extraction in Quick Look Preview (`ArchiveFolderList.preview`)
- **Location:** `Packages/ZeigKit/Sources/ArchiveFeature/ArchiveView.swift:225-244`
- **Vulnerability & Mechanics:**
  When a user taps any file row inside an open archive, `ArchiveFolderList.preview` extracts the entry to `FileManager.default.temporaryDirectory`:
  ```swift
  let result = try await model.actions.withPassword(for: model.url, initial: model.password) { (password) throws(ArchiveError) in
      try await service.extract(listing, entries: [entry], to: folder, password: password)
  }
  ```
  1. **No size check or decompression quota:** Tapping a multi-gigabyte file (or a zip-bomb entry) immediately starts decompressing the entire stream into `tmp/` (and for solid 7z/RAR or streaming `libarchive` archives, decompresses everything preceding that entry too).
  2. **No `operation.run` wrapper or cancellation:** Unlike `ArchiveActions.extract`, `preview` does not run inside `model.actions.operation.run("…")` and passes `progress: .none`. Consequently, **no progress overlay is shown and the user cannot cancel the operation**.
- **Recommendation:**
  Wrap `service.extract` inside `model.actions.operation.run("Preparing preview…") { progress in ... }` so the user sees progress and can cancel, and warn or refuse Quick Look preview if `entry.size` exceeds a safe threshold (e.g., 250 MB) or available disk space.

---

### [SEC-06] Low — Predictable Temporary Filenames in `rars-ffi` Multi-Volume Writer (`write_volumes`) & Unzeroed Passwords in C++ Heap
- **Locations:**
  - `Native/rars-ffi/src/lib.rs:438-443` (`write_volumes`)
  - `Native/zeig7z/src/zeig7z.cpp:250, 288, 303, 673, 923`
- **Vulnerability & Mechanics:**
  1. In `Native/rars-ffi/src/lib.rs`, `write_volumes` creates temporary volume files with a static pattern:
     ```rust
     let temporary = self.destination.with_file_name(format!(".zeig-volume-{index}.tmp"));
     let file = fs::File::create(&temporary)?;
     ```
     If two operations write volumes in the same directory or if a `.zeig-volume-0.tmp` file/symlink already exists, `File::create` clobbers or follows it. Including a unique token or using `OpenOptions::new().write(true).create_new(true)` avoids collisions.
  2. In `Native/zeig7z/src/zeig7z.cpp`, passwords stored in `UString` (`zeig7z_archive::password`, `COpenCallback::password`, `CExtractCallback::password`, `CUpdateCallback::password`) are freed without scrubbing memory (`memset_s`) upon `zeig7z_close` or callback destruction.

---

## 2. Functional Bugs & Edge Cases

### [BUG-01] High — Creating Split RAR Archives Silently Overwrites Existing Split Archives and Mixes Leftover Volumes
- **Locations:**
  - `Packages/ZeigKit/Sources/ArchiveFeature/PackSheet.swift:198` (`PackSheet.create`)
  - `Native/rars-ffi/src/lib.rs:459-469` (`write_volumes`)
- **Reproduction & Root Cause:**
  1. User creates a split RAR archive named `"Archive"` in a folder. `rars` writes `"Archive.part1.rar"`, `"Archive.part2.rar"`, `"Archive.part3.rar"`. Note that `"Archive.rar"` **does not exist** on disk.
  2. User selects another set of files in the same folder and creates another split RAR archive with the default name `"Archive"`.
  3. `PackSheet.create()` computes:
     ```swift
     let destination = FileNaming.unique(sources.folder.appendingPathComponent(name + "." + format.fileExtension))
     ```
     Because `FileNaming.unique` only checks `fileExists(atPath: ".../Archive.rar")`, it sees `false` and returns `.../Archive.rar` instead of `"Archive 2.rar"`!
  4. `write_volumes` in `Native/rars-ffi/src/lib.rs:467` then executes `fs::rename(temporary, &final_path)` onto `"Archive.part1.rar"`, `"Archive.part2.rar"`, **silently overwriting the user's previous split archive**!
  5. Worse still: if the first archive had 3 parts (`part1`..`part3`) and the new archive has 2 parts (`part1`..`part2`), `"Archive.part3.rar"` from the old archive remains on disk. Immediately afterwards, `ArchiveService.verifyWithSevenZip` (and `volume_paths` in `lib.rs:358`) discovers all 3 files (`part1`..`part3`), mixing the new archive with the old volume 3!
- **Recommendation:**
  Update `FileNaming.unique` (or `PackSheet.create`) to also check for existing `.part1.<ext>` / `.part01.<ext>` / `.part001.<ext>` files so `FileNaming.unique` picks `"Archive 2.rar"`, and guard against overwriting existing files in `write_volumes`.

---

### [BUG-02] High — Concurrent `Task` Spawning in `FileMenu` ("Extract N Archives") Corrupts `OperationModel` and Leaks `CheckedContinuation`
- **Locations:**
  - `Packages/ZeigKit/Sources/ArchiveFeature/FileActionViews.swift:54-56, 70-74` (`FileMenu`)
  - `Packages/ZeigKit/Sources/ArchiveFeature/ArchiveActions.swift:44, 70-74` (`ArchiveActions.askPassword`)
- **Reproduction & Root Cause:**
  In `FileMenu` (`FileActionViews.swift:54-56`), when multiple archives are selected and the user long-presses and chooses **"Extract N Archives"**:
  ```swift
  Button("Extract \(items.count) Archives", systemImage: "arrow.down.doc") {
      for item in items { extract(item) }
  }
  ```
  `extract(_:)` spawns a separate unstructured `Task` for **every archive simultaneously**, all sharing the single `model.actions` (`ArchiveActions`) and `model.actions.operation` (`OperationModel`) instance:
  1. All $N$ tasks concurrently enter `operation.run("Extracting…")`, resetting `counters` and racing on `self.title`. As soon as the fastest archive finishes, its `defer { self.title = nil }` dismisses the progress overlay while the remaining archives are still extracting in the background.
  2. If two archives are password-protected, the second task's call to `askPassword` overwrites `actions.passwordPrompt` while the first task is suspended on its `CheckedContinuation<String?, Never>`, **leaking the first continuation** (`SWIFT TASK CONTINUATION MISUSE`) and hanging that task permanently.
- **Recommendation:**
  Extract multiple archives sequentially in a single `Task` (like `SelectionToolbar.extract()` does at line 167), and only set `actions.extracted` after the batch finishes.

---

### [BUG-03] Medium — `RecentStore` and `FolderModel.expanded` Break When a Folder is Renamed, Moved, or Deleted
- **Locations:**
  - `Packages/ZeigKit/Sources/ZeigStore/RecentStore.swift:59-62, 72-76` (`remove`, `move`)
  - `Packages/ZeigKit/Sources/ArchiveFeature/FolderView.swift:256-288` (`rename`, `moved`)
  - `Packages/ZeigKit/Sources/ArchiveFeature/FolderModel.swift:154-184` (`delete`, `newFolder`)
- **Reproduction & Root Cause:**
  `RecentStore.move(_ oldPath: String, to newPath: String)` and `RecentStore.remove(_ relativePath: String)` only match `entry.relativePath == oldPath`:
  ```swift
  public func move(_ oldPath: String, to newPath: String) {
      guard let index = entries.firstIndex(where: { $0.relativePath == oldPath }) else { return }
      entries[index].relativePath = newPath
      save()
  }
  ```
  When a user renames, moves, or groups a **folder** (e.g., `"Trips"` $\to$ `"Holidays"`), any files inside that folder recorded in `RecentStore` (e.g., `"Trips/rome.zip"`) keep their old prefix `"Trips/..."` and disappear from the Recent tab on the next prune. Similarly, deleting a folder `"Trips"` via `FolderModel.delete` only calls `recent.remove("Trips")`, leaving descendant entries (`"Trips/rome.zip"`) in `recent.entries`, and renaming an expanded folder causes it to collapse because `FolderModel.expanded` is not updated.
- **Recommendation:**
  Update `RecentStore.move` and `RecentStore.remove` to also update/remove descendants matching `entry.relativePath.hasPrefix(oldPath + "/")`:
  ```swift
  public func move(_ oldPath: String, to newPath: String) {
      let prefix = oldPath + "/"
      var changed = false
      for index in entries.indices {
          if entries[index].relativePath == oldPath {
              entries[index].relativePath = newPath
              changed = true
          } else if entries[index].relativePath.hasPrefix(prefix) {
              entries[index].relativePath = newPath + "/" + entries[index].relativePath.dropFirst(prefix.count)
              changed = true
          }
      }
      if changed { save() }
  }
  ```

---

### [BUG-04] Medium — Partial Extraction in `RarsBackend.extract` Silently Drops Empty Folders
- **Location:** `Packages/ZeigKit/Sources/ZeigBackends/RarsBackend.swift:53-64`
- **Reproduction & Root Cause:**
  When `rars` is used to open a RAR archive (`rarsOpensRar == true`) and the user long-presses a folder inside `ArchiveView` and selects **"Extract Folder"**, `RarsBackend.extract` extracts the archive to `scratch` and then loops over `entries`:
  ```swift
  for entry in entries where !entry.isDirectory {
  ```
  Because directory entries are skipped by `where !entry.isDirectory`, extracting an empty folder (or a folder tree containing empty subfolders) never creates those empty directories in `destination`.
- **Recommendation:**
  Create directories for `entry where entry.isDirectory` (using `FileManager.default.createDirectory(at: destination.appendingPathComponent(relative), withIntermediateDirectories: true)`) before or during the move loop.

---

### [BUG-05] Medium — `RarsBackend.test` and `ArchiveService.verifyWithSevenZip` Ignore Progress and Cannot Be Cancelled
- **Locations:**
  - `Packages/ZeigKit/Sources/ZeigBackends/RarsBackend.swift:67-69` (`RarsBackend.test`)
  - `Native/rars-ffi/src/lib.rs:283-285` (`test_archive`)
  - `Packages/ZeigKit/Sources/ZeigBackends/ArchiveService.swift:134, 149-153` (`verifyWithSevenZip`)
- **Reproduction & Root Cause:**
  1. `RarsBackend.test` accepts `progress: ArchiveProgress`, but ignores it and calls `testArchive(path: archive.path, password: password)` in Rust, which calls `run_extraction(&path, None, password, None)`. As a result, testing a RAR archive with `rars` shows no progress percentage and **cannot be cancelled** via the Cancel button in `OperationOverlay`.
  2. In `ArchiveService.create`, after `rars` finishes writing a RAR archive, `Self.verifyWithSevenZip(first, request: request)` calls `sevenZip.test(archive, format: .rar, password: password, progress: .none)`. During this verification pass (which decompresses the entire archive), the Cancel button in `OperationOverlay` does nothing because `.none` always returns `true`.
- **Recommendation:**
  Add `progress: Option<Arc<dyn RarProgress>>` to `test_archive` in `Native/rars-ffi/src/lib.rs`, forward `ProgressRelay(progress)` in `RarsBackend.test`, and pass `progress` into `verifyWithSevenZip`.

---

### [BUG-06] Medium — Duplicate Entry Paths in an Archive Cause `ArchiveTree.Node.id` Collisions in SwiftUI `List`
- **Location:** `Packages/ZeigKit/Sources/ZeigCore/ArchiveTree.swift:9-19, 43`
- **Reproduction & Root Cause:**
  `ArchiveTree.Node` uses `public var id: String { path }` (the sanitized relative path). Valid `tar`, `cpio`, `7z`, and `zip` archives can contain multiple entries that resolve to the same `sanitizedPath` (for example, `tar -rf` appended updates where the same filename appears twice in the archive, or two entries `"./file.txt"` and `"../file.txt"` that both sanitize to `"file.txt"`).
  `ArchiveTree.init` appends both `Node`s to `files[parent]` with identical `id` values, which triggers SwiftUI `List` / `UICollectionView` duplicate-ID assertion warnings and broken selection/preview behavior.
- **Recommendation:**
  Either deduplicate `files[parent]` by `path` (keeping the latest entry, matching extraction overwrite semantics while accumulating `entriesUnder` for both) or include `entry?.index` in `Node.id`.

---

### [BUG-07] Low / Medium — `FolderModel` Back/Forward History Can Navigate Into Deleted or Renamed Folders
- **Location:** `Packages/ZeigKit/Sources/ArchiveFeature/FolderModel.swift:34-35, 92-102, 131-145`
- **Reproduction & Root Cause:**
  In `BrowseView` (`navigatesInPlace == true`), if a user navigates into a subfolder, goes Back to root, deletes or renames that subfolder, and then taps Forward in `HistoryButtons`, `FolderModel.goForward()` sets `self.folder` to the deleted folder's `URL`. Subsequent attempts to create a folder or import files inside that deleted directory fail with an I/O error.
- **Recommendation:**
  In `FolderModel.reload(_ library: FileLibrary)`, prune `backStack` and `forwardStack` of any non-`nil` URLs that no longer exist on disk, and if `self.folder` itself no longer exists, fall back to `nil` (root).

---

### [BUG-08] Low — Hidden Archive Creation When Name Starts With `.` in `PackSheet` and Missing `errno` Check in `LibArchiveBackend.readError`
- **Locations:**
  - `Packages/ZeigKit/Sources/ArchiveFeature/PackSheet.swift:197`
  - `Packages/ZeigKit/Sources/ZeigBackends/LibArchiveBackend.swift:377-387`
- **Reproduction & Root Cause:**
  1. Unlike `FileLibrary.safeName` (which strips leading `.` and `:`), `PackSheet.create()` only replaces `/` with `-`. If a user types a name starting with `.` (e.g., `.secret`), the created archive `.secret.zip` is hidden by `FileLibrary.contents(of:)` (`options: [.skipsHiddenFiles]`), making it invisible in Browse and Search. Use `FileLibrary.safeName` (or move `safeName` to `FileNaming`) in `PackSheet.create()`.
  2. In `LibArchiveBackend.readError`, filesystem errors (`ENOENT`, `EACCES`, `EIO`) during `archive_read_open_filename` or `archive_read_data_block` are unconditionally mapped to `.corrupt(detail: message)` instead of checking `archive_errno(reader) != 0` to return `.io(detail: message)`. Because `.corrupt.allowsFallback` is `true`, missing/unreadable files trigger an unnecessary fallback attempt and display `"The archive is damaged."` instead of `"A file couldn't be read or written."`.

---

## 3. Performance & Scalability Issues

### [PERF-01] High — $O(N \cdot D)$ Memory Duplication and `@MainActor` Blocking in `ArchiveTree.init`
- **Locations:**
  - `Packages/ZeigKit/Sources/ZeigCore/ArchiveTree.swift:22-45`
  - `Packages/ZeigKit/Sources/ArchiveFeature/ArchiveView.swift:31`
- **Analysis:**
  1. **Main-thread execution:** `ArchiveModel.load` calls `tree = ArchiveTree(entries: listing.entries)` directly on `@MainActor` after `actions.open` returns.
  2. **$O(N \cdot D)$ memory amplification:** Inside `ArchiveTree.init`:
     ```swift
     for depth in 0..<parts.count {
         let ancestor = parts[0..<depth].joined(separator: "/")
         entriesUnder[ancestor, default: []].append(entry)
     ```
     Every `ArchiveEntry` is appended to `entriesUnder[ancestor]` for **every ancestor level** from `""` down to its parent directory. For an archive with $N = 100,000$ entries at an average nesting depth of $D = 6$, `entriesUnder` stores $600,000+$ `ArchiveEntry` copies in memory (with `entriesUnder[""]` duplicating the entire archive's entry array), even though `entries(for: node)` is only ever called when the user long-presses a single folder to extract it.
- **Recommendation:**
  - Remove `entriesUnder` from `ArchiveTree` entirely and compute `entries(for: node)` on demand when extracting a folder:
    ```swift
    public func entries(for node: Node) -> [ArchiveEntry] {
        guard node.isDirectory else { return node.entry.map { [$0] } ?? [] }
        let prefix = node.path + "/"
        return allEntries.filter {
            guard let p = $0.sanitizedPath else { return false }
            return p == node.path || p.hasPrefix(prefix)
        }
    }
    ```
  - Construct `ArchiveTree` off the main actor (e.g., inside `ArchiveService.open` or a detached task).

---

### [PERF-02] Medium / High — Synchronous Recursive Directory Enumeration on `@MainActor` in `SearchView` and Redundant Per-Keystroke Sorting
- **Locations:**
  - `Packages/ZeigKit/Sources/SearchFeature/SearchView.swift:62-69, 73, 103, 127`
  - `Packages/ZeigKit/Sources/ZeigStore/FileLibrary.swift:63-72`
- **Analysis:**
  1. In `SearchView.swift:127`, `.task(id: library.changeCount) { everything = library.allItems() }` runs `FileLibrary.allItems()` synchronously on `@MainActor`. If the user has extracted a large archive containing thousands of files into the app's library, `FileManager.enumerator` blocks the UI thread while statting every file in the directory tree.
  2. In `SearchView.body`, `matches(_ scope: SearchScope)` is called **3 times on every keystroke**: once for `let results = matches(scope)` (line 73), and twice inside the `ScopeSwitcher` label closure (`matches(.all).count` and `matches(.archives).count` at line 103). The two calls inside `ScopeSwitcher` sort the entire filtered array (`localizedStandardCompare`) just to read `.count`.
- **Recommendation:**
  - Perform the recursive `FileManager.enumerator` traversal in a background task and hop back to `@MainActor` with the `[FileItem]` array.
  - Compute the filtered matches for `.all` once per `body` evaluation, derive `.archives` by filtering `.isArchive`, and only sort the active scope's array.

---

### [PERF-03] Medium — Repeated Synchronous Disk `stat` Calls on Every `RecentView.body` Evaluation
- **Location:** `Packages/ZeigKit/Sources/RecentFeature/RecentView.swift:35-45, 163`
- **Analysis:**
  In `RecentView`:
  ```swift
  private var rows: [Row] {
      recent.entries.compactMap { entry in
          library.item(atRelativePath: entry.relativePath).map { Row(entry: entry, item: $0) }
      }
  }
  ```
  `rows` is a computed property evaluated inside `body` (`let rows = rows` at line 44) and evaluated a **second time** in `.onChange(of: rows.map(\.item), initial: true)` at line 163. Each evaluation performs up to $2 \times 100 = 200$ synchronous `fileExists` + `resourceValues` filesystem syscalls on `@MainActor` whenever any state in `RecentView` changes (such as tapping rows during multi-selection).
- **Recommendation:**
  Pass the already-computed `let rows = rows` into `.onChange(of: rows.map(\.item))`, or cache `rows` in `@State` updated via `.task(id: "\(library.changeCount)|\(recent.entries.count)")`.

---

### [PERF-04] Medium — `ThumbnailCache` Full-Flush Eviction Cliff (`removeAll`) and Unbounded `misses` Set
- **Location:** `Packages/ZeigKit/Sources/ZeigDesign/FileThumbnail.swift:54-80`
- **Analysis:**
  ```swift
  if let image {
      if images.count > 400 { images.removeAll() }
      images[key] = image
  } else {
      misses.insert(key)
  }
  ```
  When the 401st thumbnail is generated, `images.removeAll()` purges all 400 cached thumbnails at once, and `images` does not respond to iOS system memory pressure warnings. Meanwhile, `misses` grows without bound.
- **Recommendation:**
  Back `ThumbnailCache` with `NSCache<NSString, CGImage>` (with `countLimit = 400`), which provides automatic LRU eviction and automatic purging under iOS memory pressure, and cap `misses` when it exceeds a threshold.

---

### [PERF-05] Low / Medium — Unbuffered File Writes in `rars-ffi` Extraction (`CountingWriter`) and Redundant Header Scans in `zeig7z_get_archive_info`
- **Locations:**
  - `Native/rars-ffi/src/lib.rs:325-330, 385-397` (`run_extraction`, `CountingWriter`)
  - `Native/zeig7z/src/zeig7z.cpp:538, 582-605` (`zeig7z_entry_at`, `zeig7z_get_archive_info`)
- **Analysis:**
  1. In `Native/rars-ffi/src/lib.rs:325`, `Box::new(fs::File::create(&target)?)` is wrapped directly by `CountingWriter` without a `std::io::BufWriter`. Every small write from the decompressor issues a raw `write(2)` syscall and crosses the UniFFI boundary into Swift (`progress.report`), acquiring the `Mutex` in `OperationModel.Counters`. Wrapping the `File` in `BufWriter::with_capacity(64 * 1024, file)` reduces both syscall and lock overhead.
  2. In `Native/zeig7z/src/zeig7z.cpp`, `zeig7z_entry_at` calls `zeig7z_entry_count(archive)` on every single index lookup, and `zeig7z_get_archive_info` re-iterates all $N$ entries calling `GetProperty(i, kpidIsDir)` and `GetProperty(i, kpidSize)` a second time after `SevenZipBackend.list` already read them.

---

## 4. Summary Priority Matrix

| ID | Category | Severity | Component | Summary |
|---|---|---|---|---|
| **SEC-01** | Security / Crash | **High** | `ZeigCore`, `ArchiveFeature`, `rars-ffi` | `UInt64` integer overflow trap when summing crafted entry `size` headers |
| **BUG-01** | Bug / Data Loss | **High** | `PackSheet`, `rars-ffi` | Split RAR creation overwrites existing `.partN.rar` files and mixes leftover volumes |
| **BUG-02** | Bug / Concurrency | **High** | `FileActionViews`, `ArchiveActions` | Extracting multiple archives from context menu spawns concurrent tasks on shared state & leaks continuations |
| **PERF-01** | Performance / Memory | **High** | `ArchiveTree`, `ArchiveView` | $O(N \cdot D)$ `entriesUnder` memory duplication & main-thread tree building |
| **SEC-02** | Security | **Medium** | `LibArchiveBackend` | Unbounded sparse file offset in `pwrite` & partial write handling |
| **SEC-03** | Security / Bug | **Medium** | `LibArchiveBackend` | Hardlinks & special files (FIFOs/devices) extracted as 0-byte regular files (truncating targets) |
| **SEC-04** | Security | **Medium** | All 3 Backends | Intermediate parent directory symlinks followed if extracting into populated destination |
| **SEC-05** | Security / UX | **Medium** | `ArchiveView` | Quick Look preview extracts arbitrarily large entries without progress overlay, cancellation, or size cap |
| **BUG-03** | Bug | **Medium** | `RecentStore`, `FolderModel` | Renaming, moving, or deleting a folder orphans/breaks descendant entries in `RecentStore` and `expanded` |
| **BUG-04** | Bug | **Medium** | `RarsBackend` | Partial RAR extraction (`entries != nil`) silently drops empty folders |
| **BUG-05** | Bug / UX | **Medium** | `RarsBackend`, `ArchiveService` | `RarsBackend.test` and `verifyWithSevenZip` ignore `ArchiveProgress` and cannot be cancelled |
| **BUG-06** | Bug | **Medium** | `ArchiveTree` | Duplicate sanitized paths in an archive produce duplicate `Node.id` values in SwiftUI `List` |
| **PERF-02** | Performance | **Medium** | `SearchView`, `FileLibrary` | Synchronous recursive `allItems()` enumeration on `@MainActor` & 3x sorting per keystroke |
| **PERF-03** | Performance | **Medium** | `RecentView` | Synchronous disk `stat` calls repeated twice per `body` evaluation for all recent items |
| **PERF-04** | Performance | **Medium** | `FileThumbnail` | `ThumbnailCache` wipes all 400 images at once instead of LRU/`NSCache` |
| **SEC-06** | Security | **Low** | `rars-ffi`, `zeig7z.cpp` | Predictable `.zeig-volume-{index}.tmp` names & unzeroed password buffers in C++ |
| **BUG-07** | Bug | **Low** | `FolderModel` | In-place back/forward history can navigate into a deleted or renamed folder URL |
| **BUG-08** | Bug | **Low** | `PackSheet`, `LibArchiveBackend` | Leading `.` in archive name creates invisible hidden archive; `readError` misclassifies I/O errors as `.corrupt` |
| **PERF-05** | Performance | **Low** | `rars-ffi`, `zeig7z.cpp` | Unbuffered `std::fs::File` in `CountingWriter` & redundant COM calls in `zeig7z_get_archive_info` |
