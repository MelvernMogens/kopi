import AppKit
import ApplicationServices
import KopiKit

/// Writes a clip back to the pasteboard and (optionally) sends ⌘V to the frontmost app.
enum Paster {
    static func write(_ clip: Clip, plain: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(clip.content, forType: .string)
        if !plain, let rtf = clip.rtf { item.setData(rtf, forType: .rtf) }
        item.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardRules.ownMarker))
        pb.writeObjects([item])
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (only once per app identity; afterwards it's a no-op).
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Posts ⌘V. Needs Accessibility; returns false (and does nothing) without it.
    @discardableResult
    static func sendPaste() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
