import AppKit
import KopiKit

/// Polls NSPasteboard.general.changeCount (there is no change notification on macOS) and records new text.
final class ClipboardMonitor {
    private let store: ClipStore
    private let prefs = Prefs.shared
    private var timer: Timer?
    private var lastChange: Int
    var onChange: (() -> Void)?

    init(store: ClipStore) {
        self.store = store
        lastChange = NSPasteboard.general.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Treat the current pasteboard contents as already seen (used after we write to it ourselves).
    func skipCurrent() { lastChange = NSPasteboard.general.changeCount }

    private func tick() {
        let pb = NSPasteboard.general
        let cc = pb.changeCount
        guard cc != lastChange else { return }
        lastChange = cc
        guard prefs.recording else { return }
        let types = (pb.types ?? []).map(\.rawValue)
        let front = NSWorkspace.shared.frontmostApplication
        if PasteboardRules.shouldIgnore(types: types, sourceBundle: front?.bundleIdentifier,
                                        ignoredBundles: Set(prefs.ignoredBundles), ignoreConcealed: prefs.ignoreConcealed) { return }
        // Text only, like CopyClip. A copied file in Finder yields its path(s) as text.
        var text = pb.string(forType: .string)
        if text == nil, let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            text = urls.map(\.path).joined(separator: "\n")
        }
        guard let text, !text.isEmpty else { return }
        var rtf = pb.data(forType: .rtf)
        if let r = rtf, r.count > 2_000_000 { rtf = nil }
        let isSelf = front?.bundleIdentifier == Bundle.main.bundleIdentifier
        store.add(text, rtf: rtf, sourceBundle: isSelf ? nil : front?.bundleIdentifier, sourceName: isSelf ? nil : front?.localizedName)
        onChange?()
    }
}
