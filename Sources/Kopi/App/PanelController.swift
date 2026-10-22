import AppKit
import SwiftUI
import KopiKit

final class KopiPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel: show/hide, positioning, keyboard handling, and the paste sequence.
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    let store: ClipStore
    let monitor: ClipboardMonitor
    let prefs = Prefs.shared
    private var panel: KopiPanel!
    private var keyMonitor: Any?
    /// App that was frontmost before the panel opened; focus returns there on hide/paste.
    private(set) var previousApp: NSRunningApplication?
    var openSettings: (() -> Void)?
    var settingsVisible: (() -> Bool)?

    static let fullSize = NSSize(width: 680, height: 440)
    static let compactSize = NSSize(width: 340, height: 440)
    /// Screen frame of the menu-bar icon; the panel drops down beneath it like CopyClip.
    var anchorRect: (() -> NSRect?)?

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        model = PanelModel(store: store)
        super.init()
        model.pasteHandler = { [weak self] c, plain in self?.paste(c, plain: plain) }
        model.copyHandler = { [weak self] c in self?.copyOnly(c) }
        model.closeHandler = { [weak self] in self?.hide() }
        model.settingsHandler = { [weak self] in self?.hide(restoreFocus: false); self?.openSettings?() }
        model.previewChanged = { [weak self] in self?.applyPreviewSize() }
        build()
    }

    private func build() {
        panel = KopiPanel(contentRect: NSRect(origin: .zero, size: Self.fullSize),
                          styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable],
                          backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 360, height: 260)
        panel.delegate = self
        let host = NSHostingView(rootView: PanelView(model: model))
        host.wantsLayer = true
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    /// When the panel last went away. Clicking the menu-bar icon first steals key focus (which can hide the panel),
    /// then delivers the click — without this guard that click would immediately reopen it.
    private var lastHidden = Date.distantPast

    /// Menu-bar icon / hotkey: open if closed, close if open. Visibility alone decides — with "Keep window open"
    /// the panel stays up without key focus, and checking isKeyWindow made it reopen instead of closing.
    func toggle() {
        debug("toggle sinceHide=\(Date().timeIntervalSince(lastHidden))")
        if panel.isVisible { hide(); return }
        if Date().timeIntervalSince(lastHidden) < 0.35 { return }
        show()
    }

    func show() {
        model.reloadFromStore()
        model.refilter(resetSelection: true)
        model.quickLook = false
        position()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // A menu-bar click is relayed by MenuBarAgent, which re-activates the previous app right after we open.
        // Take focus back once that settles so typing goes into the search field.
        for delay in [0.08, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
                self.model.focusToken += 1
            }
        }
        installKeyMonitor()
        model.focusToken += 1
    }

    func hide(restoreFocus: Bool = true) {
        guard panel.isVisible else { return }
        lastHidden = Date()
        panel.orderOut(nil)
        if restoreFocus, NSApp.isActive, !(settingsVisible?() ?? false) { previousApp?.activate() }
        removeKeyMonitor()
        model.editing = nil
        model.quickLook = false
        if prefs.clearSearchOnHide { model.query = ""; model.filter = .all }
    }

    func windowDidResignKey(_ notification: Notification) {
        debug("resignKey")
        if !prefs.keepWindowOpen && model.editing == nil { hide(restoreFocus: false) } else { removeKeyMonitor() }
    }

    func windowDidBecomeKey(_ notification: Notification) { installKeyMonitor(); debug("becameKey") }

    func debug(_ what: String) {
        guard ProcessInfo.processInfo.environment["KOPI_DEBUG"] != nil else { return }
        NSLog("KOPI_DEBUG \(what) key=\(panel.isKeyWindow) active=\(NSApp.isActive) visible=\(panel.isVisible) query=\(model.query) sel=\(model.selected?.title.prefix(30) ?? "-") filter=\(model.filter.rawValue) pinned=\(store.pinned.count) quickLook=\(model.quickLook) editing=\(model.editing != nil)")
    }

    func windowDidResize(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: model.showPreview ? "panelSizeFull" : "panelSizeCompact")
    }

    private func position() {
        if ProcessInfo.processInfo.environment["KOPI_DEBUG"] != nil { NSLog("KOPI_DEBUG anchor raw=\(String(describing: anchorRect?())) screens=\(NSScreen.screens.map(\.frame))") }
        let anchor = anchorRect?().flatMap { r -> NSRect? in
            r.width > 0 && r.height > 0 && NSScreen.screens.contains { $0.frame.intersects(r) } ? r : nil
        }
        let mouse = NSEvent.mouseLocation
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } }
            ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let key = model.showPreview ? "panelSizeFull" : "panelSizeCompact"
        var size = model.showPreview ? Self.fullSize : Self.compactSize
        if let s = UserDefaults.standard.string(forKey: key) { let v = NSSizeFromString(s); if v.width >= 360, v.height >= 260 { size = v } }
        let vf = screen.visibleFrame
        size.width = min(size.width, vf.width - 40)
        size.height = min(size.height, vf.height - 40)
        // Under the icon, right edges aligned with the icon's centre area; clamped inside the screen.
        // No usable icon frame (hidden behind the notch / menu-bar allow list): use CopyClip's spot, top-right.
        var x = anchor.map { $0.midX - 40 } ?? (vf.maxX - size.width - 150)
        x = min(x, vf.maxX - 8 - size.width)
        x = max(vf.minX + 8, x)
        let y = vf.maxY - 6 - size.height
        panel.setFrame(NSRect(x: x, y: max(vf.minY + 8, y), width: size.width, height: size.height), display: true)
    }

    /// Called when the preview is toggled so the panel grows/shrinks around its left edge.
    func applyPreviewSize() {
        guard panel.isVisible else { return }
        let key = model.showPreview ? "panelSizeFull" : "panelSizeCompact"
        var size = model.showPreview ? Self.fullSize : Self.compactSize
        if let s = UserDefaults.standard.string(forKey: key) { let v = NSSizeFromString(s); if v.width >= 360, v.height >= 260 { size = v } }
        var f = panel.frame
        let top = f.maxY
        // Keep the left edge where it is (list stays under the icon); grow right, clamp to the screen.
        f.size = size
        f.origin.y = top - size.height
        if let vf = panel.screen?.visibleFrame { f.origin.x = max(vf.minX + 8, min(f.origin.x, vf.maxX - 8 - size.width)) }
        panel.setFrame(f, display: true, animate: false)
    }

    // MARK: Paste

    private func copyOnly(_ c: Clip) {
        Paster.write(c, plain: prefs.pastePlainText)
        monitor.skipCurrent()
        store.markUsed(c.id, bump: prefs.moveUsedToTop)
        model.reloadFromStore()
    }

    private func paste(_ c: Clip, plain: Bool) {
        Paster.write(c, plain: plain)
        monitor.skipCurrent()
        store.markUsed(c.id, bump: prefs.moveUsedToTop)
        let keepOpen = prefs.keepWindowOpen
        panel.orderOut(nil)
        removeKeyMonitor()
        previousApp?.activate()
        guard prefs.pasteDirectly else {
            model.reloadFromStore()
            if keepOpen { panel.orderFrontRegardless() } else if prefs.clearSearchOnHide { model.query = "" }
            return
        }
        if !Paster.hasAccessibility {
            Paster.requestAccessibility()
            model.reloadFromStore()
            return
        }
        // Give the target app a beat to regain key focus after our panel goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            Paster.sendPaste()
            guard let self else { return }
            self.model.reloadFromStore()
            if keepOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.panel.orderFrontRegardless() }
            } else {
                self.model.editing = nil
                if self.prefs.clearSearchOnHide { self.model.query = ""; self.model.filter = .all }
            }
        }
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            let used = self.handle(e)
            self.debug("key \(e.keyCode) used=\(used)")
            return used ? nil : e
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Returns true when the key was consumed.
    private func handle(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let m = model
        if m.editing != nil { return false }   // edit sheet owns the keyboard
        switch (e.keyCode, flags) {
        case (53, []):  // esc
            if m.quickLook { m.quickLook = false } else if !m.query.isEmpty { m.query = "" } else { hide() }
            return true
        case (125, []), (45, [.control]): m.move(1); return true          // ↓, ⌃N
        case (126, []), (35, [.control]): m.move(-1); return true         // ↑, ⌃P
        case (125, [.command]): m.moveToEdge(top: false); return true
        case (126, [.command]): m.moveToEdge(top: true); return true
        case (121, _): m.move(8); return true                             // page down
        case (116, _): m.move(-8); return true                            // page up
        case (36, []), (76, []): m.paste(); return true                   // ↩
        case (36, [.shift]), (36, [.option]): m.paste(plain: true); return true
        case (48, []): cycleFilter(1); return true                        // ⇥
        case (48, [.shift]): cycleFilter(-1); return true
        case (49, []) where m.query.isEmpty || m.quickLook:                // space = quick look
            m.quickLook.toggle(); return true
        case (16, [.command]): m.quickLook.toggle(); return true          // ⌘Y
        case (35, [.command]): m.togglePin(); return true                 // ⌘P
        case (14, [.command]): m.beginEdit(); return true                 // ⌘E
        case (51, [.command]): m.delete(); return true                    // ⌘⌫
        case (8, [.command]):                                             // ⌘C
            if let fe = panel.firstResponder as? NSTextView, fe.selectedRange().length > 0 { return false }
            m.copy(); return true
        case (42, [.command]): m.showPreview.toggle(); return true   // ⌘\
        case (43, [.command]): hide(restoreFocus: false); openSettings?(); return true       // ⌘,
        case (3, [.command]): m.focusToken += 1; return true              // ⌘F
        case (13, [.command]): hide(); return true                        // ⌘W
        default: break
        }
        if flags == [.command], let n = Self.digit(e.keyCode) {           // ⌘1…⌘9, ⌘0
            m.paste(index: n == 0 ? 9 : n - 1)
            return true
        }
        return false
    }

    private func cycleFilter(_ d: Int) {
        let all = Filter.allCases
        let i = all.firstIndex(of: model.filter) ?? 0
        model.filter = all[(i + d + all.count) % all.count]
    }

    static func digit(_ code: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0][code]
    }
}
