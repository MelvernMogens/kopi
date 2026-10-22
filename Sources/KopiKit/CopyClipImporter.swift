import Foundation

/// Reads CopyClip 2's Core Data store (~/Library/Application Support/CopyClip/copyclip.sqlite) without touching it:
/// the db + WAL + SHM are copied to a temp dir first, so a running CopyClip is never disturbed.
public enum CopyClipImporter {
    public static var defaultPath: String {
        NSHomeDirectory() + "/Library/Application Support/CopyClip/copyclip.sqlite"
    }

    /// Core Data stores dates as seconds since 2001-01-01.
    static let coreDataEpoch: TimeInterval = 978_307_200

    public static func read(path: String = defaultPath) throws -> [Clip] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }
        let tmp = fm.temporaryDirectory.appendingPathComponent("kopi-import-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let dst = tmp.appendingPathComponent("copyclip.sqlite").path
        for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: path + suffix) {
            try fm.copyItem(atPath: path + suffix, toPath: dst + suffix)
        }
        let db = try SQLiteDB(path: dst)
        var apps: [Int64: (String?, String?)] = [:]
        try? db.query("SELECT Z_PK, ZBUNDLE, ZNAME FROM ZSOURCEAPP") { r in
            apps[r.int(0)] = (r.text(1), r.text(2).map(cleanName))
        }
        var out: [Clip] = []
        try db.query("SELECT ZCONTENTS, ZDISPLAYTITLE, ZPINNED, ZTOTALPASTES, ZSOURCE, ZDATERECORDED FROM ZCLIPPING ORDER BY ZDATERECORDED ASC") { r in
            guard let content = r.text(0), !content.isEmpty else { return }
            let date = Date(timeIntervalSince1970: r.double(5) + coreDataEpoch)
            let src = r.isNull(4) ? nil : apps[r.int(4)]
            out.append(Clip(content: content, name: r.text(1), pinned: r.int(2) != 0, created: date, lastUsed: date,
                            pasteCount: Int(r.int(3)), sourceBundle: src?.0, sourceName: src?.1))
        }
        return out
    }

    /// CopyClip stores some names with invisible direction marks (e.g. "\u{200E}WhatsApp").
    static func cleanName(_ s: String) -> String {
        s.unicodeScalars.filter { !(0x200B...0x200F).contains($0.value) && $0.value != 0xFEFF }.map(String.init).joined()
    }
}
