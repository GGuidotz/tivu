// I tasti volume su, volume giù e muto della tastiera. Per riceverli (e non farli arrivare al Mac quando comandano la
// TV) serve un filtro degli eventi di sistema, che macOS concede solo con il permesso Accessibilità.
// Il filtro guarda soltanto gli eventi dei tasti multimediali: non vede lettere, numeri né scorciatoie.

import AppKit
import ApplicationServices

enum MediaKey: Int {
    case volumeUp = 0, volumeDown = 1, mute = 7
}

@MainActor
final class MediaKeys {
    static let shared = MediaKeys()

    /// Chiamato a ogni pressione (anche ripetuta tenendo premuto). Vero: il tasto è per la TV e il Mac non lo vede.
    var handler: ((MediaKey) -> Bool)?
    /// Vero se in questo momento i tasti vanno alla TV: serve a far sparire anche il rilascio del tasto.
    var isActive: (() -> Bool)?

    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Chiede il permesso: macOS mostra la sua finestra con il pulsante per aprire le impostazioni.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Accende il filtro. Falso se manca il permesso.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1) << 14   // NX_SYSDEFINED: i tasti multimediali
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: nil)
        else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    fileprivate func handle(_ key: MediaKey, down: Bool) -> Bool {
        if down { return handler?(key) ?? false }
        return isActive?() ?? false
    }
}

/// Il filtro vive sul ciclo principale, quindi questa funzione gira sul thread principale.
private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            if let tap = MediaKeys.shared.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        return pass
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
    let data = ns.data1
    let flags = data & 0xFFFF
    guard let key = MediaKey(rawValue: (data & 0xFFFF_0000) >> 16) else { return pass }
    let down = ((flags & 0xFF00) >> 8) == 0xA
    let consumed = MainActor.assumeIsolated { MediaKeys.shared.handle(key, down: down) }
    return consumed ? nil : pass
}
