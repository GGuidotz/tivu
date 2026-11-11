// La voce nella barra dei menu e il suo pannello. Un NSStatusItem con un simbolo che dice lo stato con la forma, non
// con il colore: televisore pieno se la TV è collegata, vuoto se è spenta, con l'altoparlante barrato se è in muto.
// Clic: apre o chiude il pannello (un popover: su macOS 26 è di vetro). Clic destro o ctrl-clic: un menu breve.
// Rotella o due dita sulla voce: volume.

import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    /// Un clic sulla voce mentre il pannello è aperto lo chiude (popover transitorio) prima che arrivi il clic: senza
    /// questo, il pannello si chiuderebbe e si riaprirebbe subito.
    private var lastClose = Date.distantPast
    private var drawn = ""
    private var scrollMonitor: Any?
    private var scrollRest = 0.0

    init(model: AppModel) {
        self.model = model
        super.init()
        item.autosaveName = "Tivu"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        model.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)
        model.prefs.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)
        // I monitor locali girano sul thread principale.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self?.scrolled(event) ?? false }
            return handled ? nil : event
        }
        redraw()
    }

    private func redraw() {
        guard let button = item.button else { return }
        let connected = model.tvState == .connected
        let symbol = !connected ? "tv" : (model.muted ? "tv.badge.minus" : "tv.fill")
        let tip = "Tivu: " + model.summary
        guard symbol + tip != drawn else { return }
        drawn = symbol + tip
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: connected ? "tv.fill" : "tv", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
    }

    /// Rotella sopra la voce: un passo di volume ogni scatto (o ogni tratto con il trackpad).
    private func scrolled(_ event: NSEvent) -> Bool {
        guard event.window === item.button?.window, model.tvState == .connected else { return false }
        scrollRest += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
        while abs(scrollRest) >= 1 {
            model.volumeStep(scrollRest > 0)
            scrollRest -= scrollRest > 0 ? 1 : -1
        }
        return true
    }

    // MARK: - Clic

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            closePanel()
        } else if Date().timeIntervalSince(lastClose) > 0.35 {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = item.button, !popover.isShown else { return }
        model.ensureConnected()
        // Il contenuto nasce all'apertura e se ne va alla chiusura: a pannello chiuso nessuna vista lavora.
        let host = NSHostingController(rootView: PanelView(model: model, prefs: model.prefs,
                                                           close: { [weak self] in self?.closePanel() }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func showMenu() {
        closePanel()
        let menu = NSMenu()
        menu.addItem(withTitle: L("Apri il pannello"), action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        if model.prefs.hasTV {
            if model.tvState == .connected {
                menu.addItem(withTitle: L("Spegni la TV"), action: #selector(turnOff), keyEquivalent: "").target = self
            } else {
                menu.addItem(withTitle: L("Accendi la TV"), action: #selector(turnOn), keyEquivalent: "").target = self
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Impostazioni…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Novità e aggiornamenti…"), action: #selector(openUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Invia un feedback…"), action: #selector(openFeedback), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Esci da Tivu"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)   // apre il menu sotto la voce, come le voci di sistema
        item.menu = nil                  // e il clic sinistro torna al pannello
    }

    @objc private func openPanelFromMenu() { showPanel() }
    @objc private func turnOff() { model.turnOff() }
    @objc private func turnOn() { model.turnOn() }
    @objc private func openSettings() { model.showSettings(.general) }
    @objc private func openUpdates() { model.showSettings(.updates) }
    @objc private func openFeedback() { model.showSettings(.feedback) }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { lastClose = Date() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { popover.contentViewController = nil }
    }
}
