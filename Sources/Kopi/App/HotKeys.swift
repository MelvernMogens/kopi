import AppKit
import Carbon
import KopiKit

/// Global hotkeys via Carbon RegisterEventHotKey — works without Accessibility permission.
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers (or re-registers) hotkey `id`. Returns false if the system refused (combo taken).
    @discardableResult
    func register(id: UInt32, _ spec: HotKeySpec, handler: @escaping () -> Void) -> Bool {
        installHandler()
        unregister(id: id)
        handlers[id] = handler
        var carbonMods: UInt32 = 0
        if spec.modifiers & HotKeySpec.command != 0 { carbonMods |= UInt32(cmdKey) }
        if spec.modifiers & HotKeySpec.option != 0 { carbonMods |= UInt32(optionKey) }
        if spec.modifiers & HotKeySpec.control != 0 { carbonMods |= UInt32(controlKey) }
        if spec.modifiers & HotKeySpec.shift != 0 { carbonMods |= UInt32(shiftKey) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, carbonMods, EventHotKeyID(signature: OSType(0x4B4F5049), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref; return true }
        return false
    }

    func unregister(id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
    }

    /// Suspend while the user records a new shortcut, so pressing the current combo doesn't fire it.
    func suspendAll() { for (_, r) in refs { UnregisterEventHotKey(r) }; refs.removeAll() }
}
