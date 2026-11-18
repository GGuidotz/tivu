// Tivu: il telecomando della TV nella barra dei menu (LSUIElement: niente Dock).
// AppModel tiene insieme il collegamento con la TV, le preferenze, i tasti volume, gli aggiornamenti e le finestre.
// Leggerezza: nessuna lettura periodica dei dati. La TV avvisa da sola quando volume o ingresso cambiano; a TV spenta
// si riprova a collegarsi solo quando serve (apri il pannello, premi un tasto volume, il Mac si sveglia, cambia
// l'uscita audio o lo schermo) e, se l'audio del Mac esce in HDMI, una volta al minuto.

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let prefs: Preferences
    let updater: Updater
    let audio = AudioOutput()
    private let lg = TVClient()
    private let android = AndroidTVClient()
    /// Il collegamento della TV abbinata, secondo il suo sistema.
    private var client: TVController { prefs.tvBrand == .android ? android : lg }

    @Published private(set) var tvState = TVState.disconnected
    /// TV Android collegata ma in standby: il collegamento resta, mancano solo volume e ingressi finché non si accende.
    @Published private(set) var tvAwake = true
    @Published private(set) var volume = 0
    @Published private(set) var muted = false
    @Published private(set) var inputs: [TVInput] = []
    @Published private(set) var foregroundApp = ""
    /// La ricerca delle TV nella rete di casa (guida e impostazioni).
    @Published private(set) var searching = false
    @Published private(set) var found: [DiscoveredTV] = []
    @Published private(set) var searchedOnce = false
    /// I tasti volume della tastiera arrivano davvero all'app (permesso Accessibilità dato e filtro acceso).
    @Published private(set) var keysRunning = false
    @Published var settingsTab: SettingsTab = .general
    /// Apre il pannello della barra (lo imposta AppDelegate): la guida ci porta l'utente alla fine.
    var openPanel: (() -> Void)?

    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let whatsNewWindow = WhatsNewWindowController()
    private var bag = Set<AnyCancellable>()
    private var retryTimer: Timer?
    private var pendingVolume: Int?
    private var volumeTimer: Timer?
    private var lastLocalVolume = Date.distantPast
    private var lastRediscovery = Date.distantPast
    private var connectedOnce = false
    private var wakeAttempts = 0

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        updater = Updater(prefs: prefs)

        for controller in [lg as TVController, android] { wire(controller) }
        android.onAwake = { [weak self] awake in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tvAwake = awake
                diag(.tv, awake ? "awake" : "standby")
            }
        }

        MediaKeys.shared.handler = { [weak self] key in self?.mediaKey(key) ?? false }
        MediaKeys.shared.isActive = { [weak self] in self?.keysGoToTV ?? false }
        prefs.$mediaKeys.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMediaKeys() }
            .store(in: &bag)
        audio.$isHDMI.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] hdmi in
                diag(.tv, "audio output \(hdmi ? "HDMI" : "other")")
                self?.scheduleRetry()
                self?.ensureConnected()
            }
            .store(in: &bag)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.ensureConnected() }
            .store(in: &bag)
        // Schermo collegato o scollegato: la TV è stata accesa, spenta o ha cambiato ingresso.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.ensureConnected() }
            .store(in: &bag)
    }

    /// Le risposte di un collegamento verso il modello (le stesse per ogni sistema di TV).
    private func wire(_ controller: TVController) {
        controller.onLog = { message in MainActor.assumeIsolated { diag(.tv, message) } }
        controller.onState = { [weak self, weak controller] state in
            MainActor.assumeIsolated {
                guard let self, let controller, controller === self.client else { return }
                self.stateChanged(state)
            }
        }
        controller.onVolume = { [weak self] volume, muted in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.muted = muted
                // Mentre trascini il cursore la TV risponde in ritardo: i suoi valori farebbero saltare il cursore.
                if Date().timeIntervalSince(self.lastLocalVolume) > 0.6 { self.volume = volume }
            }
        }
        controller.onForegroundApp = { [weak self] app in MainActor.assumeIsolated { self?.foregroundApp = app } }
        controller.onClientKey = { [weak self] key in
            MainActor.assumeIsolated {
                guard let self, self.prefs.clientKey != key else { return }
                self.prefs.clientKey = key
                diag(.tv, "paired")
            }
        }
        controller.onKeyRejected = { [weak self] in
            MainActor.assumeIsolated {
                self?.prefs.clientKey = nil
                diag(.tv, "saved key rejected: pairing again")
                self?.connect()
            }
        }
    }

    func didLaunch() {
        diag(.app, "launched \(appVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        updater.start()
        refreshMediaKeys()
        scheduleRetry()
        ensureConnected()
    }

    // MARK: - Stato in una frase

    /// L'ingresso che la TV mostra adesso, se è uno dei suoi ingressi (e non un'app della TV).
    var currentInput: TVInput? { inputs.first { !$0.appId.isEmpty && $0.appId == foregroundApp } }

    /// Gli ingressi HDMI, quelli a cui si collega un Mac.
    var hdmiInputs: [TVInput] { inputs.filter { $0.id.uppercased().hasPrefix("HDMI") } }

    var tvTitle: String {
        if prefs.tvBrand == .android {
            if !prefs.tvName.isEmpty { return prefs.tvName }
            return prefs.tvModel.isEmpty ? prefs.tvBrand.label : prefs.tvModel
        }
        if !prefs.tvModel.isEmpty { return "LG \(prefs.tvModel)" }
        return prefs.tvName.isEmpty ? L("TV") : prefs.tvName
    }

    /// La TV risponde ai comandi: collegata e non in standby.
    var isOn: Bool { tvState == .connected && tvAwake }

    var summary: String {
        guard prefs.hasTV else { return L("Nessuna TV abbinata") }
        switch tvState {
        case .connecting: return L("Cerco la TV…")
        case .pairing:
            return prefs.tvBrand == .android ? L("Scrivi il codice mostrato sulla TV")
                                             : L("Accetta la richiesta sulla TV con il telecomando")
        case .disconnected: return L("Spenta o non raggiungibile")
        case .connected:
            if !tvAwake { return L("In standby") }
            let level = muted ? L("muto") : L("volume %d", volume)
            if let input = currentInput { return "\(input.title) · \(level)" }
            return L("Accesa") + " · " + level
        }
    }

    // MARK: - Collegamento

    private func stateChanged(_ state: TVState) {
        let previous = tvState
        tvState = state
        diag(.tv, "state \(state)")
        switch state {
        case .connected:
            connectedOnce = true
            wakeAttempts = 0
            client.inputs { [weak self] list in MainActor.assumeIsolated { self?.inputs = list } }
            client.modelName { [weak self] name in
                MainActor.assumeIsolated { if let name, !name.isEmpty { self?.prefs.tvModel = name } }
            }
            rememberMAC()
        case .disconnected:
            inputs = []
            tvAwake = true
            foregroundApp = ""
            // Tentativo fallito (non una TV che si spegne): forse il router le ha dato un altro indirizzo.
            if previous == .connecting { rediscoverIfMoved() }
        default:
            break
        }
    }

    func connect() {
        guard let host = prefs.tvHost else { return }
        client.connect(host: host, clientKey: prefs.clientKey)
    }

    /// Riprova se la TV è abbinata e il collegamento non c'è. Costa un tentativo di pochi secondi, e solo quando serve.
    func ensureConnected() {
        guard prefs.hasTV, tvState == .disconnected else { return }
        connect()
    }

    /// Con l'audio del Mac in HDMI la TV è probabilmente in uso: se il collegamento manca, un tentativo al minuto.
    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
        guard audio.isHDMI else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureConnected() }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    /// L'indirizzo fisico della TV, letto una volta appena collegati: serve per accenderla da spenta.
    private func rememberMAC() {
        guard let host = prefs.tvHost else { return }
        DispatchQueue.global(qos: .utility).async {
            let mac = TVDiscovery.macAddress(of: host)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let mac, AppModel.shared.prefs.tvMAC != mac { AppModel.shared.prefs.tvMAC = mac }
                }
            }
        }
    }

    /// La TV non risponde al suo indirizzo: se nella rete ce n'è una sola (o quella con lo stesso indirizzo fisico) a
    /// un indirizzo diverso, è lei. Al massimo una ricerca ogni cinque minuti.
    private func rediscoverIfMoved() {
        guard connectedOnce || prefs.clientKey != nil, Date().timeIntervalSince(lastRediscovery) > 300 else { return }
        lastRediscovery = Date()
        TVDiscovery.search { [weak self] list in
            MainActor.assumeIsolated {
                guard let self, self.tvState == .disconnected, let old = self.prefs.tvHost else { return }
                let same = list.first { $0.mac != nil && $0.mac == self.prefs.tvMAC } ?? (list.count == 1 ? list.first : nil)
                guard let tv = same, tv.host != old else { return }
                diag(.tv, "TV found at a new address")
                self.prefs.tvHost = tv.host
                self.connect()
            }
        }
    }

    // MARK: - Ricerca e abbinamento

    func search() {
        guard !searching else { return }
        searching = true
        TVDiscovery.search { [weak self] list in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.searching = false
                self.searchedOnce = true
                self.found = list
                diag(.tv, "search: \(list.count) found")
            }
        }
    }

    /// Sceglie una TV trovata (o un indirizzo scritto a mano) e avvia l'abbinamento: la TV mostra la richiesta.
    func pair(host: String, name: String = "", model: String = "", mac: String? = nil, brand: TVBrand = .lg) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        if prefs.tvHost != host || prefs.tvBrand != brand { prefs.clientKey = nil }
        lg.disconnect(); android.disconnect()
        prefs.tvBrand = brand
        prefs.tvHost = host
        prefs.tvName = name
        prefs.tvModel = model
        prefs.tvMAC = mac
        connect()
    }

    /// Il codice a 6 caratteri che la TV Android mostra durante l'abbinamento. Falso se non può essere quello giusto.
    @discardableResult
    func submitPairingCode(_ code: String) -> Bool {
        android.submitPairingCode(code)
    }

    func forgetTV() {
        lg.disconnect(); android.disconnect()
        prefs.forgetTV()
        found = []
        searchedOnce = false
    }

    // MARK: - Comandi

    /// Dal cursore: il valore si vede subito, alla TV va al più una richiesta ogni 80 ms (l'ultima).
    func setVolume(_ value: Int) {
        let value = max(0, min(100, value))
        volume = value
        lastLocalVolume = Date()
        pendingVolume = value
        guard volumeTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.volumeTimer = nil
                if let v = self.pendingVolume { self.client.setVolume(v) }
                self.pendingVolume = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        volumeTimer = timer
    }

    func volumeStep(_ up: Bool) {
        if up { client.volumeUp() } else { client.volumeDown() }
    }

    func toggleMute() {
        muted.toggle()
        client.setMute(muted)
    }

    func switchInput(_ input: TVInput) {
        client.switchInput(input.id)
    }

    func press(_ button: TVButton) {
        client.press(button)
    }

    func turnOff() {
        diag(.tv, "turn off")
        client.turnOff()
    }

    /// Accende la TV dalla rete e riprova a collegarsi mentre si avvia (ci mette una decina di secondi).
    func turnOn() {
        // TV Android in standby con il collegamento aperto: basta il tasto di accensione.
        if prefs.tvBrand == .android, tvState == .connected { android.wake(); return }
        guard let mac = prefs.tvMAC else { ensureConnected(); return }
        let sent = WakeOnLAN.wake(mac: mac)
        diag(.tv, "wake sent: \(sent)")
        wakeAttempts = 4
        retryAfterWake()
    }

    private func retryAfterWake() {
        guard wakeAttempts > 0 else { return }
        wakeAttempts -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tvState != .connected else { return }
                self.ensureConnected()
                self.retryAfterWake()
            }
        }
    }

    // MARK: - Tasti volume

    /// I tasti della tastiera vanno alla TV: scelta accesa, TV collegata e (se chiesto) audio del Mac in HDMI.
    var keysGoToTV: Bool {
        guard isOn else { return false }
        switch prefs.mediaKeys {
        case .never: return false
        case .always: return true
        case .hdmi: return audio.isHDMI
        }
    }

    private func mediaKey(_ key: MediaKey) -> Bool {
        guard keysGoToTV else {
            // TV abbinata ma collegamento caduto: il tasto resta al Mac, e intanto si riprova per il prossimo.
            if prefs.mediaKeys != .never, audio.isHDMI { ensureConnected() }
            return false
        }
        switch key {
        case .volumeUp: volumeStep(true)
        case .volumeDown: volumeStep(false)
        case .mute: toggleMute()
        }
        return true
    }

    /// Accende o spegne il filtro dei tasti secondo la scelta e il permesso. Da richiamare dopo aver dato il permesso.
    func refreshMediaKeys() {
        if prefs.mediaKeys == .never {
            MediaKeys.shared.stop()
        } else {
            MediaKeys.shared.start()
        }
        let running = MediaKeys.shared.isRunning
        if running != keysRunning {
            keysRunning = running
            diag(.app, "media keys \(running ? "on" : "off")")
        }
    }

    // MARK: - Finestre

    func showSettings(_ tab: SettingsTab?) {
        if let tab { settingsTab = tab }
        settingsWindow.show(model: self)
    }

    /// La guida dei primi passi: da sola al primo avvio, poi da Impostazioni › Generale.
    func showOnboarding() {
        onboardingWindow.show(model: self)
    }

    /// Le novità: da sole dopo un aggiornamento, oppure da Impostazioni › Aggiornamenti.
    func showWhatsNewIfUpdated(firstLaunch: Bool) {
        whatsNewWindow.showIfUpdated(firstLaunch: firstLaunch)
    }

    func showWhatsNew() {
        whatsNewWindow.showCurrent()
    }
}
