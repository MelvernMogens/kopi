import Foundation

/// Filters + ranks clips for the search field.
/// - Every whitespace-separated token must appear (case/diacritic-insensitive) in the content, name, or source app.
/// - Ranking: pinned first, then name/title hits, then everything else by the store's order (recency).
/// - A token like `app:chrome` or `type:link` filters by source app / kind instead of text.
public enum ClipSearch {
    public struct Query: Equatable {
        public var terms: [String] = []
        public var app: String?
        public var kind: ClipKind?
        public var pinnedOnly = false
        public var isEmpty: Bool { terms.isEmpty && app == nil && kind == nil && !pinnedOnly }
    }

    public static func parse(_ raw: String) -> Query {
        var q = Query()
        for tok in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = tok.lowercased()
            if lower.hasPrefix("app:"), tok.count > 4 { q.app = fold(String(tok.dropFirst(4))); continue }
            if lower.hasPrefix("type:") || lower.hasPrefix("kind:") {
                let v = lower.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                if let k = ClipKind.allCases.first(where: { $0.rawValue == v || $0.rawValue.hasPrefix(v) && !v.isEmpty }) { q.kind = k; continue }
            }
            if lower == "is:pinned" || lower == "pinned:" { q.pinnedOnly = true; continue }
            q.terms.append(fold(tok))
        }
        return q
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }

    /// Folded, length-capped search text for a clip. Callers may cache this per clip id.
    public static func haystack(_ c: Clip) -> String {
        let body = c.content.count > 50_000 ? String(c.content.prefix(50_000)) : c.content
        return fold(body) + "\n" + fold(c.name ?? "") + "\n" + fold(c.sourceName ?? "")
    }

    public static func filter(_ clips: [Clip], query raw: String, haystack hay: ((Clip) -> String)? = nil) -> [Clip] {
        let q = parse(raw)
        if q.isEmpty { return clips }
        let hayFor = hay ?? haystack
        var scored: [(Clip, Int, Int)] = []
        for (idx, c) in clips.enumerated() {
            if q.pinnedOnly && !c.pinned { continue }
            if let k = q.kind, c.kind != k { continue }
            if let a = q.app {
                let src = fold((c.sourceName ?? "") + " " + (c.sourceBundle ?? ""))
                if !src.contains(a) { continue }
            }
            if q.terms.isEmpty { scored.append((c, 0, idx)); continue }
            let title = fold(c.title)
            let hay = hayFor(c)
            var ok = true
            var score = 0
            for t in q.terms {
                if title.contains(t) { score += title.hasPrefix(t) ? 3 : 2 } else if hay.contains(t) { score += 1 } else { ok = false; break }
            }
            if ok { scored.append((c, score, idx)) }
        }
        scored.sort { a, b in
            if a.0.pinned != b.0.pinned { return a.0.pinned }
            // Strong title hits float up; otherwise keep recency order.
            let sa = a.1 >= q.terms.count * 2 ? 1 : 0, sb = b.1 >= q.terms.count * 2 ? 1 : 0
            if sa != sb { return sa > sb }
            return a.2 < b.2
        }
        return scored.map(\.0)
    }

    /// Ranges of every term occurrence in `text`, for highlight rendering.
    public static func highlightRanges(in text: String, query raw: String) -> [Range<String.Index>] {
        let q = parse(raw)
        var out: [Range<String.Index>] = []
        for t in q.terms where !t.isEmpty {
            var start = text.startIndex
            while start < text.endIndex,
                  let r = text.range(of: t, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: start..<text.endIndex) {
                out.append(r)
                start = r.upperBound
            }
        }
        return out
    }
}

public enum RelativeTime {
    /// "now", "4m", "2h", "3d", "5w", "Mar 4" — compact like CopyClip's site mockup but shorter.
    public static func short(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "now" }
        if s < 3600 { return "\(Int((s / 60).rounded()))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 86400 * 7 { return "\(Int(s / 86400))d" }
        if s < 86400 * 30 { return "\(Int(s / (86400 * 7)))w" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }
}
