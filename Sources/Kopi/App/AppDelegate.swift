import AppKit
import SwiftUI
import KopiKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var store: ClipStore!
    var monitor: ClipboardMonitor!
    var panel: PanelController!
    var settings: SettingsController!
    var statusItem: NSStatusItem!
    let prefs = Prefs.shared
    let args = CommandLine.arguments

    static var dataDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kopi")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let dbPath = argValue("--db") ?? Self.dataDir.appendingPathComponent("kopi.sqlite").path
        do {
            store = try ClipStore(path: dbPath, historyLimit: prefs.historyLimit)
        } catch {
            let a = NSAlert(); a.messageText = "Kopi couldn't open its history"; a.informativeText = "\(error)"; a.runModal()
            NSApp.terminate(nil); return
        }

        if !args.contains("--no-import") {
            let migrated = prefs.migrateFromCopyClip()
            if !migrated.isEmpty { NSLog("Kopi: migrated CopyClip prefs: \(migrated.joined(separator: ", "))") }
            if store.meta("importedCopyClip") == nil {
                let r = importCopyClip()
                NSLog("Kopi: first-launch import: \(r)")
            }
        }
        store.historyLimit = prefs.historyLimit

        monitor = ClipboardMonitor(store: store)
        panel = PanelController(store: store, monitor: monitor)
        settings = SettingsController(store: store)
        panel.openSettings = { [weak self] in self?.settings.show() }
        panel.anchorRect = { [weak self] in self?.statusItem?.button?.window?.frame }
        panel.settingsVisible = { [weak self] in self?.settings.isVisible ?? false }
        settings.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        settings.onImport = { [weak self] in self?.importCopyClip() ?? "" }
        monitor.onChange = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.panel.model.reloadFromStore()
        }
        monitor.start()
        NotificationCenter.default.addObserver(forName: .kopiHotKeysChanged, object: nil, queue: .main) { [weak self] _ in self?.registerHotKeys() }

        setupStatusItem()
        registerHotKeys()

        if ProcessInfo.processInfo.environment["KOPI_DEBUG"] != nil {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.panel.debug("tick anchor=\(String(describing: self?.statusItem?.button?.window?.frame)) vis=\(self?.statusItem?.isVisible ?? false)")
            }
        }
        if args.contains("--open") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.panel.show() } }
        if args.contains("--settings") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.settings.show() } }
        if args.contains("--menu") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showPopupMenu() } }
    }

    private func argValue(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @discardableResult
    func importCopyClip() -> String {
        do {
            let clips = try CopyClipImporter.read()
            if clips.isEmpty { store.setMeta("importedCopyClip", "none"); return "No CopyClip history found." }
            let added = store.importClips(clips)
            store.setMeta("importedCopyClip", ISO8601DateFormatter().string(from: Date()))
            panel?.model.reloadFromStore()
            return "Imported \(added) of \(clips.count) clips\(added < clips.count ? " (rest were already here)" : "")."
        } catch {
            return "Import failed: \(error)"
        }
    }

    // MARK: Hotkeys

    func registerHotKeys() {
        let a = HotKeys.shared.register(id: 1, prefs.panelHotKey) { [weak self] in self?.panel.toggle() }
        let b = HotKeys.shared.register(id: 2, prefs.menuHotKey) { [weak self] in self?.showPopupMenu() }
        if !a || !b { NSLog("Kopi: hotkey registration failed panel=\(a) menu=\(b)") }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Kopi")
            b.image?.isTemplate = true
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
    }

    func updateStatusIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: prefs.recording ? "list.clipboard" : "pause.circle",
                                           accessibilityDescription: "Kopi")
        statusItem.button?.image?.isTemplate = true
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if ProcessInfo.processInfo.environment["KOPI_DEBUG"] != nil { panel.debug("statusClicked type=\(e?.type.rawValue ?? 0)") }
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true || e?.modifierFlags.contains(.option) == true {
            let m = statusMenu()
            statusItem.menu = m
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle()
        }
    }

    private func statusMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item("Open Kopi", key: "", #selector(openPanel)))
        m.addItem(.separator())
        let rec = item(prefs.recording ? "Pause Recording" : "Resume Recording", key: "", #selector(toggleRecording))
        m.addItem(rec)
        m.addItem(item("Clear History (keep pins)", key: "", #selector(clearHistory)))
        m.addItem(.separator())
        m.addItem(item("Settings…", key: ",", #selector(openSettings)))
        m.addItem(item("Quit Kopi", key: "q", #selector(quit)))
        return m
    }

    private func item(_ title: String, key: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openPanel() { panel.show() }
    @objc private func openSettings() { settings.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleRecording() { prefs.recording.toggle(); updateStatusIcon() }
    @objc private func clearHistory() { store.deleteAll(includingPinned: false); panel.model.reloadFromStore() }

    // MARK: Pop-up menu at cursor (CopyClip's second hotkey)

    private var menuTarget: NSRunningApplication?

    func showPopupMenu() {
        panel.hide()
        menuTarget = NSWorkspace.shared.frontmostApplication
        let m = NSMenu()
        m.autoenablesItems = false
        let pinned = store.pinned.prefix(9)
        let recent = store.history.prefix(15)
        var n = 0
        func add(_ c: Clip) {
            let title = c.title.count > 60 ? String(c.title.prefix(60)) + "…" : c.title
            let key = n < 10 ? "\(n == 9 ? 0 : n + 1)" : ""
            let i = NSMenuItem(title: title, action: #selector(popupPick(_:)), keyEquivalent: key)
            i.keyEquivalentModifierMask = []
            i.target = self
            i.representedObject = NSNumber(value: c.id)
            i.image = NSImage(systemSymbolName: c.pinned ? "pin" : c.kind.symbol, accessibilityDescription: nil)
            i.toolTip = String(c.content.prefix(400))
            m.addItem(i)
            n += 1
        }
        if !pinned.isEmpty {
            m.addItem(NSMenuItem.sectionHeader(title: "Pinned"))
            pinned.forEach(add)
        }
        if !recent.isEmpty {
            m.addItem(NSMenuItem.sectionHeader(title: "Recent"))
            recent.forEach(add)
        }
        if n == 0 { let e = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: ""); e.isEnabled = false; m.addItem(e) }
        m.addItem(.separator())
        m.addItem(item("Open Kopi…", key: "", #selector(openPanel)))
        NSApp.activate(ignoringOtherApps: true)
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // popUp blocks until dismissed; if nothing picked, hand focus back.
        if pendingPick == nil { menuTarget?.activate() }
        if let id = pendingPick { pendingPick = nil; pasteFromMenu(id) }
    }

    private var pendingPick: Int64?

    @objc private func popupPick(_ sender: NSMenuItem) {
        pendingPick = (sender.representedObject as? NSNumber)?.int64Value
    }

    private func pasteFromMenu(_ id: Int64) {
        guard let c = store.clip(id) else { return }
        Paster.write(c, plain: prefs.pastePlainText)
        monitor.skipCurrent()
        store.markUsed(id, bump: prefs.moveUsedToTop)
        menuTarget?.activate()
        guard prefs.pasteDirectly else { return }
        if !Paster.hasAccessibility { Paster.requestAccessibility(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Paster.sendPaste() }
    }
}
