import Foundation

/// What a clip looks like, inferred from its text. Drives the row glyph and the preview style.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, code, color, email, number, path

    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .email: return "at"
        case .number: return "number"
        case .path: return "folder"
        }
    }

    public var label: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .email: return "Email"
        case .number: return "Number"
        case .path: return "Path"
        }
    }

    /// Cheap, deterministic classifier. Order matters: the most specific shapes first.
    public static func classify(_ raw: String) -> ClipKind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .text }
        let singleLine = !s.contains("\n")
        if singleLine, s.count <= 9, s.range(of: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil {
            return .color
        }
        if singleLine, s.range(of: #"^(?:rgba?|hsla?)\(\s*[\d.%\s,/]+\)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .color
        }
        if singleLine, !s.contains(" "), s.range(of: #"^(?:https?|ftp|file|ssh|mailto|ws|wss)://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .link
        }
        if singleLine, !s.contains(" "), s.range(of: #"^(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}(?:/\S*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           s.range(of: #"\.(?:com|net|org|io|dev|app|ai|co|id|me|gg|xyz|so|sh)(?:/|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .link
        }
        if singleLine, s.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .email
        }
        if singleLine, s.range(of: #"^[-+]?[\d.,]+%?$"#, options: .regularExpression) != nil, s.rangeOfCharacter(from: .decimalDigits) != nil {
            return .number
        }
        if singleLine, (s.hasPrefix("/") || s.hasPrefix("~/")), !s.contains("  "), s.count < 400,
           s.range(of: #"^~?/[^\s]*(?:[^\s]| (?=\S))*$"#, options: .regularExpression) != nil, s.filter({ $0 == "/" }).count >= 2 {
            return .path
        }
        if looksLikeCode(s) { return .code }
        return .text
    }

    /// Shell sessions / CLI output: prompts, "usage:" lines, "Last login" banners. Rendered monospaced in previews.
    public static func looksLikeTerminal(_ s: String) -> Bool {
        let sample = s.count > 4000 ? String(s.prefix(4000)) : s
        if sample.hasPrefix("Last login:") { return true }
        if sample.range(of: #"(?m)^\S+@\S+ [^\n]*[%$#] "#, options: .regularExpression) != nil { return true }
        if sample.range(of: #"(?m)^(usage|Usage|error|Error|fatal|Traceback):"#, options: .regularExpression) != nil,
           sample.contains("\n") { return true }
        return false
    }

    static func looksLikeCode(_ s: String) -> Bool {
        var score = 0
        let markers = ["{", "}", "();", "=>", "->", "func ", "function ", "const ", "let ", "var ", "import ", "def ", "class ",
                       "return ", "#include", "</", "/>", "SELECT ", "select ", "npm ", "pip ", "git ", "sudo ", "curl ",
                       "export ", "brew ", "cd ", "&&", "||", "!=", "==", "::", "$(", "`"]
        for m in markers where s.contains(m) { score += 1 }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if indented * 3 >= lines.count { score += 2 }
            let semis = lines.filter { $0.hasSuffix(";") || $0.hasSuffix("{") || $0.hasSuffix("}") }.count
            if semis * 3 >= lines.count { score += 2 }
        }
        // Prose has lots of plain words and sentence punctuation; a single marker in prose is not code.
        let words = s.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let sentenceEnds = s.filter { $0 == "." || $0 == "?" || $0 == "!" }.count
        if words > 25, sentenceEnds * 12 > words, score < 4 { return false }
        return score >= 2
    }
}

/// One clipboard history entry.
public struct Clip: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var content: String
    /// RTF data captured alongside the plain string, if the source offered rich text.
    public var rtf: Data?
    /// Optional user-given name (CopyClip's "display title").
    public var name: String?
    public var kind: ClipKind
    public var pinned: Bool
    /// Order inside the pinned section (ascending). Ignored when not pinned.
    public var pinOrder: Double
    public var created: Date
    /// Last time this clip was copied or pasted. Unpinned clips sort by this, newest first.
    public var lastUsed: Date
    public var pasteCount: Int
    public var sourceBundle: String?
    public var sourceName: String?

    public init(id: Int64 = 0, content: String, rtf: Data? = nil, name: String? = nil, kind: ClipKind? = nil,
                pinned: Bool = false, pinOrder: Double = 0, created: Date = Date(), lastUsed: Date? = nil,
                pasteCount: Int = 0, sourceBundle: String? = nil, sourceName: String? = nil) {
        self.id = id
        self.content = content
        self.rtf = rtf
        self.name = name
        self.kind = kind ?? ClipKind.classify(content)
        self.pinned = pinned
        self.pinOrder = pinOrder
        self.created = created
        self.lastUsed = lastUsed ?? created
        self.pasteCount = pasteCount
        self.sourceBundle = sourceBundle
        self.sourceName = sourceName
    }

    /// One-line title for list rows: the custom name, else the first non-empty line with whitespace collapsed.
    public var title: String {
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return Clip.oneLine(content)
    }

    public static func oneLine(_ s: String, limit: Int = 300) -> String {
        let firstLine = s.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        var collapsed = firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        // Drop decorative rules around a heading ("── Hermes error details ──" → "Hermes error details").
        let deco = CharacterSet(charactersIn: "─━—–-=_*#~•·│|╭╮╰╯ ")
        let trimmed = collapsed.trimmingCharacters(in: deco)
        if trimmed.count >= 3 { collapsed = trimmed }
        if collapsed.isEmpty { return s.isEmpty ? "(empty)" : "(whitespace)" }
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    public var lineCount: Int { content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count }
    public var wordCount: Int { content.split(whereSeparator: { $0.isWhitespace }).count }
}
