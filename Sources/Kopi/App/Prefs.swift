import AppKit
import KopiKit
import Combine

/// UserDefaults-backed settings. Every property writes through on change.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var panelHotKey: HotKeySpec { didSet { save(panelHotKey, "panelHotKey") } }
    @Published var menuHotKey: HotKeySpec { didSet { save(menuHotKey, "menuHotKey") } }
    @Published var pasteDirectly: Bool { didSet { d.set(pasteDirectly, forKey: "pasteDirectly") } }
    @Published var pastePlainText: Bool { didSet { d.set(pastePlainText, forKey: "pastePlainText") } }
    @Published var keepWindowOpen: Bool { didSet { d.set(keepWindowOpen, forKey: "keepWindowOpen") } }
    @Published var clearSearchOnHide: Bool { didSet { d.set(clearSearchOnHide, forKey: "clearSearchOnHide") } }
    @Published var moveUsedToTop: Bool { didSet { d.set(moveUsedToTop, forKey: "moveUsedToTop") } }
    @Published var pinsToTop: Bool { didSet { d.set(pinsToTop, forKey: "pinsToTop") } }
    @Published var singleClickPaste: Bool { didSet { d.set(singleClickPaste, forKey: "singleClickPaste") } }
    @Published var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    @Published var recording: Bool { didSet { d.set(recording, forKey: "recording") } }
    @Published var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var themeID: String { didSet { d.set(themeID, forKey: "themeID") } }
    @Published var showPreview: Bool { didSet { d.set(showPreview, forKey: "showPreview") } }
    @Published var ignoredBundles: [String] { didSet { d.set(ignoredBundles, forKey: "ignoredBundles") } }

    private init() {
        d.register(defaults: [
            "pasteDirectly": true, "pastePlainText": false, "keepWindowOpen": false, "clearSearchOnHide": true,
            "moveUsedToTop": true, "pinsToTop": true, "singleClickPaste": false, "ignoreConcealed": true,
            "recording": true, "historyLimit": 500, "themeID": "graphite", "showPreview": false,
            "ignoredBundles": PasteboardRules.defaultIgnored,
        ])
        panelHotKey = Self.load("panelHotKey", d) ?? .defaultPanel
        menuHotKey = Self.load("menuHotKey", d) ?? .defaultMenu
        pasteDirectly = d.bool(forKey: "pasteDirectly")
        pastePlainText = d.bool(forKey: "pastePlainText")
        keepWindowOpen = d.bool(forKey: "keepWindowOpen")
        clearSearchOnHide = d.bool(forKey: "clearSearchOnHide")
        moveUsedToTop = d.bool(forKey: "moveUsedToTop")
        pinsToTop = d.bool(forKey: "pinsToTop")
        singleClickPaste = d.bool(forKey: "singleClickPaste")
        ignoreConcealed = d.bool(forKey: "ignoreConcealed")
        recording = d.bool(forKey: "recording")
        historyLimit = d.integer(forKey: "historyLimit")
        themeID = d.string(forKey: "themeID") ?? "graphite"
        showPreview = d.bool(forKey: "showPreview")
        ignoredBundles = d.stringArray(forKey: "ignoredBundles") ?? PasteboardRules.defaultIgnored
    }

    private func save(_ h: HotKeySpec, _ key: String) {
        if let data = try? JSONEncoder().encode(h) { d.set(data, forKey: key) }
    }

    private static func load(_ key: String, _ d: UserDefaults) -> HotKeySpec? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeySpec.self, from: data)
    }

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? .graphite }

    /// One-time: carry over the user's CopyClip 2 settings (hotkeys, keep-open, paste directly, theme, ignore list).
    func migrateFromCopyClip() -> [String] {
        guard !d.bool(forKey: "migratedCopyClipPrefs"), let cc = UserDefaults(suiteName: "com.fiplab.copyclip2") else { return [] }
        d.set(true, forKey: "migratedCopyClipPrefs")
        var changed: [String] = []
        if let code = cc.object(forKey: "HotKeyCode") as? Int, let mods = cc.object(forKey: "HotKeyModifierKey") as? Int, mods != 0 {
            panelHotKey = HotKeySpec(keyCode: UInt32(code), modifiers: UInt(mods)); changed.append("panel hotkey \(panelHotKey.display)")
        }
        if let code = cc.object(forKey: "MenuHotKeyCode") as? Int, let mods = cc.object(forKey: "MenuHotKeyModifierKey") as? Int, mods != 0 {
            menuHotKey = HotKeySpec(keyCode: UInt32(code), modifiers: UInt(mods)); changed.append("menu hotkey \(menuHotKey.display)")
        }
        if let v = cc.object(forKey: "KeepWindowOpen") as? Bool { keepWindowOpen = v; changed.append("keep open \(v)") }
        if let v = cc.object(forKey: "PasteDirectly") as? Bool { pasteDirectly = v; changed.append("paste directly \(v)") }
        if let v = cc.object(forKey: "ClearSearchOnHide") as? Bool { clearSearchOnHide = v; changed.append("clear search \(v)") }
        if let v = cc.object(forKey: "PasteOriginalFormat") as? Bool { pastePlainText = !v; changed.append("plain text \(!v)") }
        if let t = cc.string(forKey: "ThemeName") {
            let map = ["CCGraphiteTheme": "graphite", "CCMidnightBlueTheme": "midnight", "CCDarkTheme": "graphite", "CCLightTheme": "light",
                       "CCForestTheme": "forest", "CCRoseTheme": "rose", "CCOceanTheme": "midnight", "CCSlateTheme": "graphite",
                       "CCLavenderTheme": "rose", "CCSunsetTheme": "rose"]
            if let id = map[t] { themeID = id; changed.append("theme \(id)") }
        }
        return changed
    }
}
