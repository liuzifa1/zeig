import Foundation

/// Names for files Zeig creates.
public enum FileNaming {
    /// `url`, or "name 2.ext", "name 3.ext", … next to it, whichever doesn't exist yet.
    /// Compound extensions stay together: "backup.tar.gz" → "backup 2.tar.gz".
    public static func unique(_ url: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let (stem, ext) = split(url.lastPathComponent)
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem) \(number)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    /// "photos.tar.gz" → ("photos", "tar.gz"); "notes" → ("notes", ""). Uses the longest
    /// extension of a known format, so "a.b.zip" → ("a.b", "zip").
    public static func split(_ fileName: String) -> (stem: String, extension: String) {
        if let format = FormatDetector.format(forName: fileName),
           let ext = format.extensions.filter({ ext in
               ext == "Z" ? fileName.hasSuffix(".Z") : fileName.lowercased().hasSuffix("." + ext.lowercased())
           }).max(by: { $0.count < $1.count }) {
            let stem = String(fileName.dropLast(ext.count + 1))
            return (stem.isEmpty ? fileName : stem, stem.isEmpty ? "" : String(fileName.suffix(ext.count)))
        }
        let ns = fileName as NSString
        let ext = ns.pathExtension
        return ext.isEmpty || ns.deletingPathExtension.isEmpty ? (fileName, "") : (ns.deletingPathExtension, ext)
    }

    /// Default name for a new archive of `sources`: the item's name for one item, else "Archive".
    public static func archiveName(for sources: [URL], format: ArchiveFormat) -> String {
        let base: String
        if sources.count == 1, let only = sources.first {
            // A single file keeps its extension in single-file formats ("log.txt.gz").
            base = format.isSingleFile ? only.lastPathComponent : split(only.lastPathComponent).stem
        } else {
            base = "Archive"
        }
        return base + "." + format.fileExtension
    }

    /// The folder an archive extracts into: next to it, named after it ("photos.zip" → "photos").
    public static func extractionFolder(for archive: URL) -> URL {
        var stem = split(archive.lastPathComponent).stem
        // "name.part1" from "name.part1.rar" → "name".
        if let range = stem.range(of: #"\.part\d+$"#, options: .regularExpression) {
            stem.removeSubrange(range)
        }
        return archive.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
    }

    /// For single-file formats: "notes.txt.gz" → "notes.txt", "data.tgz" → "data.tar".
    public static func decompressedName(for archive: URL) -> String {
        let name = archive.lastPathComponent
        let (stem, ext) = split(name)
        switch ext.lowercased() {
        case "tgz", "tbz", "tbz2", "txz", "tzst": return stem + ".tar"
        case "": return name + ".out"
        default: return stem
        }
    }
}
