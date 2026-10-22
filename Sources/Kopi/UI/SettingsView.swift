import SwiftUI
import AppKit
import ServiceManagement
import KopiKit

final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let store: ClipStore
    var onHotKeysChanged: (() -> Void)?
    var onImport: (() -> String)?

    init(store: ClipStore) { self.store = store }
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, onHotKeysChanged: { [weak self] in self?.onHotKeysChanged?() },
                                    onImport: { [weak self] in self?.onImport?() ?? "" })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { HotKeyRecorderState.shared.stop() }
}

enum SettingsTab: String, CaseIterable { case general = "General", pasting = "Pasting", history = "History", privacy = "Privacy" }

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    let store: ClipStore
    let onHotKeysChanged: () -> Void
    let onImport: () -> String
    @State private var tab: SettingsTab = .general
    @State private var axTrusted = Paster.hasAccessibility
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var importResult = ""
    @State private var confirmDelete: Bool? = nil
    @State private var newIgnore = ""

    var t: Theme { prefs.theme }

    var body: some View {
        ZStack {
            VisualEffect(material: t.dark ? .hudWindow : .popover)
            t.tint.opacity(t.tintOpacity)
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tb in
                        Text(tb.rawValue)
                            .font(.system(size: 12, weight: tab == tb ? .semibold : .regular))
                            .foregroundStyle(tab == tb ? t.text : t.tertiary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab == tb ? t.field : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { tab = tb }
                    }
                }
                .padding(.top, 14).padding(.bottom, 10)
                Rectangle().fill(t.hairline).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .general: general
                        case .pasting: pasting
                        case .history: history
                        case .privacy: privacy
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                }
            }
        }
        .environment(\.colorScheme, t.dark ? .dark : .light)
        .frame(width: 520, height: 470)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in axTrusted = Paster.hasAccessibility }
    }

    // MARK: Tabs

    @ViewBuilder private var general: some View {
        group("Shortcuts") {
            row("Open Kopi", "Search panel, centred on the active screen") {
                HotKeyField(spec: $prefs.panelHotKey, theme: t, onChange: onHotKeysChanged)
            }
            row("Pop-up menu", "Compact menu at the mouse pointer") {
                HotKeyField(spec: $prefs.menuHotKey, theme: t, onChange: onHotKeysChanged)
            }
        }
        group("Behaviour") {
            toggle("Start at login", nil, isOn: Binding(get: { loginOn }, set: { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                loginOn = SMAppService.mainApp.status == .enabled
            }))
            toggle("Keep window open", "Stay on screen after pasting or switching apps", isOn: $prefs.keepWindowOpen)
            toggle("Clear search on hide", nil, isOn: $prefs.clearSearchOnHide)
            toggle("Show preview pane", "⌘\\ toggles it from the panel", isOn: $prefs.showPreview)
        }
        group("Theme") {
            HStack(spacing: 10) {
                ForEach(Theme.all) { th in
                    VStack(spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(th.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                RoundedRectangle(cornerRadius: 2).fill(th.accent).frame(width: 26, height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(th.secondary.opacity(0.6)).frame(width: 34, height: 3)
                                RoundedRectangle(cornerRadius: 2).fill(th.secondary.opacity(0.4)).frame(width: 22, height: 3)
                            }
                        }
                        .frame(width: 56, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(prefs.themeID == th.id ? t.accent : t.hairline, lineWidth: prefs.themeID == th.id ? 2 : 1))
                        Text(th.name).font(.system(size: 10.5)).foregroundStyle(prefs.themeID == th.id ? t.text : t.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { prefs.themeID = th.id }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var pasting: some View {
        group("Direct paste") {
            toggle("Paste directly into the active app", "Selecting a clip pastes it — no ⌘V needed", isOn: $prefs.pasteDirectly)
            HStack(spacing: 8) {
                Circle().fill(axTrusted ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(axTrusted ? "Accessibility access granted" : "Needs Accessibility access to send ⌘V")
                    .font(.system(size: 11.5)).foregroundStyle(t.secondary)
                Spacer()
                if !axTrusted {
                    smallButton("Grant…") { Paster.requestAccessibility(); Paster.openAccessibilitySettings() }
                }
            }
            .padding(.vertical, 6)
        }
        group("Format") {
            toggle("Always paste as plain text", "⇧↩ pastes plain text one-off either way", isOn: $prefs.pastePlainText)
        }
        group("Clicks") {
            toggle("Single-click pastes", "Off: double-click or ↩ pastes", isOn: $prefs.singleClickPaste)
            toggle("Move used clips to the top", nil, isOn: $prefs.moveUsedToTop)
        }
    }

    @ViewBuilder private var history: some View {
        group("History") {
            row("Keep up to", "Pinned clips never count toward this") {
                HStack(spacing: 6) {
                    TextField("", value: $prefs.historyLimit, format: .number)
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(t.text)
                        .frame(width: 54).padding(.horizontal, 6).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(t.field))
                        .onSubmit { prefs.historyLimit = max(1, min(prefs.historyLimit, 9999)); store.historyLimit = prefs.historyLimit }
                    Text("clips").font(.system(size: 11.5)).foregroundStyle(t.tertiary)
                }
            }
            toggle("Add new pins to the top", nil, isOn: $prefs.pinsToTop)
        }
        group("Import") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from CopyClip 2").font(.system(size: 12.5)).foregroundStyle(t.text)
                    Text(importResult.isEmpty ? "Copies history, names and pins. CopyClip is left untouched." : importResult)
                        .font(.system(size: 11)).foregroundStyle(t.tertiary)
                }
                Spacer()
                smallButton("Import") { importResult = onImport() }
            }
            .padding(.vertical, 6)
        }
        group("Clear") {
            HStack(spacing: 8) {
                if confirmDelete == nil {
                    smallButton("Delete all except pinned") { confirmDelete = false }
                    smallButton("Delete everything", destructive: true) { confirmDelete = true }
                } else {
                    Text(confirmDelete == true ? "Delete every clip, including pins?" : "Delete all unpinned clips?")
                        .font(.system(size: 11.5)).foregroundStyle(t.secondary)
                    Spacer()
                    smallButton("Cancel") { confirmDelete = nil }
                    smallButton("Delete", destructive: true) { store.deleteAll(includingPinned: confirmDelete == true); confirmDelete = nil }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var privacy: some View {
        group("Recording") {
            toggle("Record clipboard", "Turn off for private mode — also in the menu bar", isOn: $prefs.recording)
            toggle("Skip passwords & concealed data", "Ignores password managers and secure fields", isOn: $prefs.ignoreConcealed)
        }
        group("Ignored apps") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(prefs.ignoredBundles, id: \.self) { b in
                    HStack(spacing: 8) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                                .font(.system(size: 12)).foregroundStyle(t.text)
                        } else {
                            Image(systemName: "app.dashed").font(.system(size: 12)).foregroundStyle(t.tertiary).frame(width: 16)
                            Text(b).font(.system(size: 12)).foregroundStyle(t.secondary)
                        }
                        Spacer()
                        Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(t.tertiary)
                            .onTapGesture { prefs.ignoredBundles.removeAll { $0 == b } }
                    }
                    .frame(height: 24)
                }
                HStack(spacing: 6) {
                    smallButton("Add app…") { pickApp() }
                    Text("Clips copied while these apps are frontmost are not recorded.")
                        .font(.system(size: 10.5)).foregroundStyle(t.tertiary)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Helpers

    private func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = true
        if p.runModal() == .OK {
            for u in p.urls { if let id = Bundle(url: u)?.bundleIdentifier, !prefs.ignoredBundles.contains(id) { prefs.ignoredBundles.append(id) } }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(t.tertiary)
                .padding(.bottom, 2)
            c()
        }
        .padding(.bottom, 14)
    }

    private func row<C: View>(_ title: String, _ sub: String?, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(t.text)
                if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(t.tertiary) }
            }
            Spacer()
            c()
        }
        .padding(.vertical, 5)
    }

    private func toggle(_ title: String, _ sub: String?, isOn: Binding<Bool>) -> some View {
        row(title, sub) { Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(t.accent) }
    }

    private func smallButton(_ title: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : t.text)
            .padding(.horizontal, 9).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.field))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(t.hairline))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

// MARK: - Hotkey recorder

final class HotKeyRecorderState: ObservableObject {
    static let shared = HotKeyRecorderState()
    @Published var activeID: UUID?
    private var monitor: Any?

    func start(_ id: UUID, onKey: @escaping (HotKeySpec?) -> Void) {
        stop()
        activeID = id
        HotKeys.shared.suspendAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if e.keyCode == 53 && f.isEmpty { onKey(nil); self?.stop(); return nil }   // esc cancels
            if f.isEmpty || f == [.shift] { NSSound.beep(); return nil }               // need a real modifier
            onKey(HotKeySpec(keyCode: UInt32(e.keyCode), modifiers: f.rawValue))
            self?.stop()
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if activeID != nil { activeID = nil; NotificationCenter.default.post(name: .kopiHotKeysChanged, object: nil) }
    }
}

extension Notification.Name { static let kopiHotKeysChanged = Notification.Name("kopiHotKeysChanged") }

struct HotKeyField: View {
    @Binding var spec: HotKeySpec
    let theme: Theme
    let onChange: () -> Void
    @ObservedObject private var rec = HotKeyRecorderState.shared
    @State private var id = UUID()

    var body: some View {
        let recording = rec.activeID == id
        Text(recording ? "Type shortcut…" : spec.display)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(recording ? theme.accent : theme.text)
            .frame(minWidth: 96).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.field))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(recording ? theme.accent : theme.hairline))
            .contentShape(Rectangle())
            .onTapGesture {
                if recording { rec.stop(); return }
                rec.start(id) { new in
                    if let new { spec = new }
                    onChange()
                }
            }
    }
}
