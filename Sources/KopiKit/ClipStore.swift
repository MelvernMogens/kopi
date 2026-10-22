import Foundation

/// Persistent clipboard history. Keeps an in-memory ordered copy for instant search;
/// every mutation writes through to SQLite.
///
/// Ordering: pinned clips first (by `pinOrder` ascending), then the rest by `lastUsed` newest-first.
public final class ClipStore: @unchecked Sendable {
    public private(set) var clips: [Clip] = []
    let db: SQLiteDB
    /// Unpinned clips beyond this count are dropped (oldest first). Pinned clips never count.
    public var historyLimit: Int { didSet { historyLimit = max(1, min(historyLimit, 9999)); trim() } }
    /// Clips longer than this are truncated on insert to keep memory sane (≈ 1 MB of text).
    public static let maxContentLength = 1_000_000

    public init(path: String, historyLimit: Int = 500) throws {
        db = try SQLiteDB(path: path)
        self.historyLimit = max(1, min(historyLimit, 9999))
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS clips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          rtf BLOB,
          name TEXT,
          kind TEXT NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          pin_order REAL NOT NULL DEFAULT 0,
          created REAL NOT NULL,
          last_used REAL NOT NULL,
          paste_count INTEGER NOT NULL DEFAULT 0,
          source_bundle TEXT,
          source_name TEXT
        );
        CREATE INDEX IF NOT EXISTS clips_content ON clips(content);
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        """)
        try reload()
    }

    public func reload() throws {
        var out: [Clip] = []
        try db.query("SELECT id, content, rtf, name, kind, pinned, pin_order, created, last_used, paste_count, source_bundle, source_name FROM clips") { r in
            out.append(Clip(id: r.int(0), content: r.text(1) ?? "", rtf: r.blob(2), name: r.text(3),
                            kind: ClipKind(rawValue: r.text(4) ?? "") ?? .text, pinned: r.int(5) != 0, pinOrder: r.double(6),
                            created: Date(timeIntervalSince1970: r.double(7)), lastUsed: Date(timeIntervalSince1970: r.double(8)),
                            pasteCount: Int(r.int(9)), sourceBundle: r.text(10), sourceName: r.text(11)))
        }
        clips = out
        sort()
    }

    func sort() {
        clips.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.pinned { return a.pinOrder == b.pinOrder ? a.id < b.id : a.pinOrder < b.pinOrder }
            return a.lastUsed == b.lastUsed ? a.id > b.id : a.lastUsed > b.lastUsed
        }
    }

    public var pinned: [Clip] { clips.filter(\.pinned) }
    public var history: [Clip] { clips.filter { !$0.pinned } }
    public func clip(_ id: Int64) -> Clip? { clips.first { $0.id == id } }

    // MARK: - Insert

    /// Records a newly copied string. If an identical clip exists it is moved to the top instead of duplicated
    /// (its name, pin and paste count are kept). Returns the clip's id, or nil for empty/whitespace-only input.
    @discardableResult
    public func add(_ rawContent: String, rtf: Data? = nil, sourceBundle: String? = nil, sourceName: String? = nil, at date: Date = Date()) -> Int64? {
        guard !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let content = rawContent.count > Self.maxContentLength ? String(rawContent.prefix(Self.maxContentLength)) : rawContent
        if let idx = clips.firstIndex(where: { $0.content == content }) {
            clips[idx].lastUsed = date
            if let sourceBundle { clips[idx].sourceBundle = sourceBundle; clips[idx].sourceName = sourceName }
            if rtf != nil { clips[idx].rtf = rtf }
            let c = clips[idx]
            try? db.run("UPDATE clips SET last_used=?, source_bundle=?, source_name=?, rtf=? WHERE id=?",
                        [.double(date.timeIntervalSince1970), .opt(c.sourceBundle), .opt(c.sourceName), .opt(c.rtf), .int(c.id)])
            sort()
            return c.id
        }
        var c = Clip(content: content, rtf: rtf, created: date, sourceBundle: sourceBundle, sourceName: sourceName)
        guard let id = try? db.run("""
            INSERT INTO clips (content, rtf, name, kind, pinned, pin_order, created, last_used, paste_count, source_bundle, source_name)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(c.content), .opt(c.rtf), .null, .text(c.kind.rawValue), .int(0), .double(0),
                  .double(date.timeIntervalSince1970), .double(date.timeIntervalSince1970), .int(0), .opt(sourceBundle), .opt(sourceName)])
        else { return nil }
        c.id = id
        clips.append(c)
        sort()
        trim()
        return id
    }

    /// Bulk insert used by the CopyClip importer. Skips content already present. Returns how many were added.
    @discardableResult
    public func importClips(_ incoming: [Clip]) -> Int {
        var existing = Set(clips.map(\.content))
        var added = 0
        try? db.exec("BEGIN")
        var nextPin = (pinned.map(\.pinOrder).max() ?? 0) + 1
        for var c in incoming {
            let t = c.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !existing.contains(c.content) else { continue }
            if c.pinned { c.pinOrder = nextPin; nextPin += 1 }
            guard let id = try? db.run("""
                INSERT INTO clips (content, rtf, name, kind, pinned, pin_order, created, last_used, paste_count, source_bundle, source_name)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """, [.text(c.content), .opt(c.rtf), .opt(c.name), .text(c.kind.rawValue), .int(c.pinned ? 1 : 0), .double(c.pinOrder),
                      .double(c.created.timeIntervalSince1970), .double(c.lastUsed.timeIntervalSince1970), .int(Int64(c.pasteCount)),
                      .opt(c.sourceBundle), .opt(c.sourceName)])
            else { continue }
            c.id = id
            clips.append(c)
            existing.insert(c.content)
            added += 1
        }
        try? db.exec("COMMIT")
        sort()
        trim()
        return added
    }

    func trim() {
        let unpinned = clips.filter { !$0.pinned }
        guard unpinned.count > historyLimit else { return }
        let drop = unpinned.suffix(unpinned.count - historyLimit).map(\.id)
        let dropSet = Set(drop)
        clips.removeAll { dropSet.contains($0.id) }
        try? db.exec("BEGIN")
        for id in drop { try? db.run("DELETE FROM clips WHERE id=?", [.int(id)]) }
        try? db.exec("COMMIT")
    }

    // MARK: - Mutations

    /// Called after a clip is pasted/copied back: bumps it to the top of history (pinned clips keep their place).
    public func markUsed(_ id: Int64, at date: Date = Date(), bump: Bool = true) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].pasteCount += 1
        if !clips[i].pinned && bump { clips[i].lastUsed = date }
        try? db.run("UPDATE clips SET paste_count=?, last_used=? WHERE id=?",
                    [.int(Int64(clips[i].pasteCount)), .double(clips[i].lastUsed.timeIntervalSince1970), .int(id)])
        sort()
    }

    /// Pins or unpins. New pins go to the top of the pinned section when `toTop` (CopyClip's default), else the bottom.
    public func setPinned(_ id: Int64, _ pinned: Bool, toTop: Bool = true) {
        guard let i = clips.firstIndex(where: { $0.id == id }), clips[i].pinned != pinned else { return }
        let orders = self.pinned.map(\.pinOrder)
        clips[i].pinned = pinned
        if pinned {
            clips[i].pinOrder = toTop ? (orders.min() ?? 1) - 1 : (orders.max() ?? -1) + 1
        } else {
            clips[i].lastUsed = Date()
        }
        try? db.run("UPDATE clips SET pinned=?, pin_order=?, last_used=? WHERE id=?",
                    [.int(pinned ? 1 : 0), .double(clips[i].pinOrder), .double(clips[i].lastUsed.timeIntervalSince1970), .int(id)])
        sort()
        if !pinned { trim() }
    }

    /// Moves a pinned clip one slot up (-1) or down (+1) within the pinned section.
    public func movePinned(_ id: Int64, by delta: Int) {
        var p = pinned
        guard let i = p.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < p.count else { return }
        p.swapAt(i, j)
        try? db.exec("BEGIN")
        for (n, c) in p.enumerated() {
            if let k = clips.firstIndex(where: { $0.id == c.id }) { clips[k].pinOrder = Double(n) }
            try? db.run("UPDATE clips SET pin_order=? WHERE id=?", [.double(Double(n)), .int(c.id)])
        }
        try? db.exec("COMMIT")
        sort()
    }

    public func rename(_ id: Int64, to name: String?) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        clips[i].name = (n?.isEmpty ?? true) ? nil : n
        try? db.run("UPDATE clips SET name=? WHERE id=?", [.opt(clips[i].name), .int(id)])
    }

    /// Replaces a clip's text. Rich text no longer matches, so it is dropped. Merges into an existing identical clip if any.
    public func edit(_ id: Int64, content: String) {
        guard let i = clips.firstIndex(where: { $0.id == id }),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let dup = clips.firstIndex(where: { $0.content == content && $0.id != id }) {
            // Keep the edited clip (it carries the user's name/pin), delete the older duplicate.
            delete(clips[dup].id)
            return edit(id, content: content)
        }
        clips[i].content = content
        clips[i].rtf = nil
        clips[i].kind = ClipKind.classify(content)
        try? db.run("UPDATE clips SET content=?, rtf=NULL, kind=? WHERE id=?", [.text(content), .text(clips[i].kind.rawValue), .int(id)])
    }

    public func delete(_ id: Int64) {
        clips.removeAll { $0.id == id }
        try? db.run("DELETE FROM clips WHERE id=?", [.int(id)])
    }

    /// Clears history. Pinned clips survive unless `includingPinned`.
    public func deleteAll(includingPinned: Bool = false) {
        if includingPinned {
            clips.removeAll()
            try? db.run("DELETE FROM clips")
        } else {
            clips.removeAll { !$0.pinned }
            try? db.run("DELETE FROM clips WHERE pinned=0")
        }
    }

    // MARK: - Meta

    public func meta(_ key: String) -> String? {
        var v: String?
        try? db.query("SELECT value FROM meta WHERE key=?", [.text(key)]) { v = $0.text(0) }
        return v
    }

    public func setMeta(_ key: String, _ value: String) {
        try? db.run("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }
}
