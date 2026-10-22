import AppKit
import SwiftUI
import KopiKit

enum Filter: String, CaseIterable, Identifiable {
    case all, pinned, links, code, text
    var id: String { rawValue }
    var label: String {
        switch self { case .all: "All"; case .pinned: "Pinned"; case .links: "Links"; case .code: "Code"; case .text: "Text" }
    }
    func matches(_ c: Clip) -> Bool {
        switch self {
        case .all: true
        case .pinned: c.pinned
        case .links: c.kind == .link || c.kind == .email
        case .code: c.kind == .code || c.kind == .path
        case .text: c.kind == .text || c.kind == .number || c.kind == .color
        }
    }
}

/// State for the panel. All access on the main thread.
final class PanelModel: ObservableObject {
    let store: ClipStore
    let prefs = Prefs.shared

    @Published var query = "" { didSet { if query != oldValue { refilter(resetSelection: true) } } }
    @Published var filter: Filter = .all { didSet { if filter != oldValue { refilter(resetSelection: true) } } }
    @Published private(set) var visible: [Clip] = []
    @Published var selectedID: Int64?
    @Published var editing: Clip?
    @Published var showPreview: Bool { didSet { prefs.showPreview = showPreview; previewChanged?() } }
    var previewChanged: (() -> Void)?
    /// Bumped to ask the search field to take focus.
    @Published var focusToken = 0
    @Published var toast: String?
    @Published var quickLook = false

    /// Called by the controller to actually paste (it owns window + timing).
    var pasteHandler: ((Clip, _ plain: Bool) -> Void)?
    var copyHandler: ((Clip) -> Void)?
    var closeHandler: (() -> Void)?
    var settingsHandler: (() -> Void)?

    private var hayCache: [Int64: (String, String)] = [:]   // id → (content snapshot key, folded)
    private var iconCache: [String: NSImage] = [:]

    init(store: ClipStore) {
        self.store = store
        showPreview = Prefs.shared.showPreview
        refilter(resetSelection: true)
    }

    var pinnedVisible: [Clip] { visible.filter(\.pinned) }
    var recentVisible: [Clip] { visible.filter { !$0.pinned } }
    var selected: Clip? { selectedID.flatMap { id in visible.first { $0.id == id } } }
    var totalCount: Int { store.clips.count }

    func reloadFromStore() { refilter(resetSelection: false) }

    func refilter(resetSelection: Bool) {
        let base = store.clips.filter(filter.matches)
        let result = ClipSearch.filter(base, query: query) { [unowned self] c in
            let key = "\(c.content.count):\(c.name ?? ""):\(c.sourceName ?? "")"
            if let hit = hayCache[c.id], hit.0 == key { return hit.1 }
            let h = ClipSearch.haystack(c)
            hayCache[c.id] = (key, h)
            return h
        }
        visible = result
        if resetSelection || selectedID == nil || !result.contains(where: { $0.id == selectedID }) {
            selectedID = result.first?.id
        }
    }

    /// The first ten visible clips get ⌘1…⌘9, ⌘0 — matching CopyClip's numbering.
    func shortcutIndex(_ c: Clip) -> Int? {
        guard let i = visible.prefix(10).firstIndex(where: { $0.id == c.id }) else { return nil }
        return i
    }

    static func shortcutLabel(_ i: Int) -> String { "⌘\(i == 9 ? 0 : i + 1)" }

    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let i = visible.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visible[max(0, min(visible.count - 1, i + delta))].id
    }

    func moveToEdge(top: Bool) { selectedID = top ? visible.first?.id : visible.last?.id }

    // MARK: Actions

    func paste(_ c: Clip? = nil, plain: Bool? = nil) {
        guard let c = c ?? selected else { return }
        pasteHandler?(c, plain ?? prefs.pastePlainText)
    }

    func paste(index: Int) {
        guard index < visible.count else { return }
        paste(visible[index])
    }

    func copy(_ c: Clip? = nil) {
        guard let c = c ?? selected else { return }
        copyHandler?(c)
        flash("Copied")
    }

    func togglePin(_ c: Clip? = nil) {
        guard let c = c ?? selected else { return }
        store.setPinned(c.id, !c.pinned, toTop: prefs.pinsToTop)
        selectedID = c.id
        refilter(resetSelection: false)
    }

    func movePinned(_ c: Clip, by d: Int) {
        store.movePinned(c.id, by: d)
        refilter(resetSelection: false)
    }

    func delete(_ c: Clip? = nil) {
        guard let c = c ?? selected else { return }
        let idx = visible.firstIndex { $0.id == c.id } ?? 0
        store.delete(c.id)
        hayCache[c.id] = nil
        refilter(resetSelection: false)
        if !visible.isEmpty { selectedID = visible[min(idx, visible.count - 1)].id }
    }

    func makePlain(_ c: Clip) {
        store.edit(c.id, content: c.content)
        refilter(resetSelection: false)
        flash("Formatting removed")
    }

    func beginEdit(_ c: Clip? = nil) {
        guard let c = c ?? selected else { return }
        editing = c
    }

    func saveEdit(id: Int64, name: String, content: String) {
        store.rename(id, to: name)
        if let c = store.clip(id), c.content != content { store.edit(id, content: content) }
        editing = nil
        hayCache[id] = nil
        refilter(resetSelection: false)
        selectedID = id
        focusToken += 1
    }

    func cancelEdit() { editing = nil; focusToken += 1 }

    func flash(_ text: String) {
        toast = text
        let t = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in if self?.toast == t { self?.toast = nil } }
    }

    func icon(for bundle: String?) -> NSImage? {
        guard let bundle, !bundle.isEmpty else { return nil }
        if let i = iconCache[bundle] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        iconCache[bundle] = img
        return img
    }
}
