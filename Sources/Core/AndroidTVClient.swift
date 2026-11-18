// Il collegamento con una TV Android / Google TV: il protocollo "Android TV Remote v2" di Google, lo stesso
// dell'app Google TV sul telefono. Due porte, tutte e due TLS con il certificato di Tivu come identità:
//   6467  abbinamento: la TV mostra un codice di 6 caratteri; Tivu lo lega alle chiavi pubbliche del Mac e della TV
//         (SHA-256) e lo rimanda; se coincide, la TV ricorda il Mac.
//   6466  telecomando: messaggi con tasti (volume, ingressi, accensione, frecce) e, in arrivo dalla TV, volume,
//         app in primo piano e se la TV è accesa o in standby.
// Il protocollo non ha un "imposta volume" né un elenco di ingressi: il volume si regola a passi, gli HDMI sono i
// tasti HDMI 1-4 di Android. Solo Foundation; tutte le chiamate e le risposte sul thread principale.

import CryptoKit
import Foundation

public final class AndroidTVClient: NSObject, TVController {
    public private(set) var state = TVState.disconnected { didSet { if state != oldValue { onState?(state) } } }
    public var onState: ((TVState) -> Void)?
    public var onVolume: ((_ volume: Int, _ muted: Bool) -> Void)?
    public var onForegroundApp: ((String) -> Void)?
    public var onClientKey: ((String) -> Void)?
    public var onKeyRejected: (() -> Void)?
    public var onLog: ((String) -> Void)?
    /// La TV è accesa (true) o in standby (false): in standby il collegamento resta e basta il tasto di accensione.
    public var onAwake: ((Bool) -> Void)?
    /// Il nome che la TV dà a se stessa (Cast), da mostrare nel pannello.
    public private(set) var model = ""

    /// Il marcatore salvato dopo l'abbinamento riuscito.
    public static let pairedMarker = "android-tv-remote-v2"

    private var host = ""
    private var pairing: AndroidTVChannel?
    private var remote: AndroidTVChannel?
    private var identity: SecIdentity?
    private var connectTimeout: Timer?
    private var pairStep = Step.idle
    private var level = 0
    private var levelMax = 0
    private var muted = false
    private var awake = true

    private enum Step { case idle, request, options, configuration, waitingForCode, secret }

    private enum Key {
        static let power = 26, volumeUp = 24, volumeDown = 25, mute = 164
        static let up = 19, down = 20, left = 21, right = 22, enter = 23
        static let back = 4, home = 3, menu = 82, escape = 111
        static let hdmi1 = 243   // 243...246: HDMI 1...4
    }

    // MARK: - Collegamento

    public func connect(host: String, clientKey: String?) {
        disconnect()
        self.host = host
        var created = false
        guard let identity = AndroidTVIdentity.load(created: &created) else {
            onLog?("no client identity (openssl failed?)")
            return
        }
        self.identity = identity
        // Identità nuova ma abbinamento salvato: la TV non ci conosce più, bisogna rifare il codice.
        let paired = clientKey != nil && !created
        state = .connecting
        armTimeout()
        if paired { openRemote() } else { openPairing() }
    }

    public func disconnect() {
        connectTimeout?.invalidate(); connectTimeout = nil
        pairing?.cancel(); pairing = nil
        remote?.cancel(); remote = nil
        pairStep = .idle
        awake = true
        state = .disconnected
    }

    /// TV spenta del tutto: l'indirizzo non risponde e il tentativo resterebbe appeso a lungo.
    private func armTimeout() {
        connectTimeout?.invalidate()
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, self.state == .connecting else { return }
            self.onLog?("connect timed out")
            self.disconnect()
        }
        RunLoop.main.add(timer, forMode: .common)
        connectTimeout = timer
    }

    // MARK: - Abbinamento (porta 6467)

    private func openPairing() {
        guard let identity, let channel = AndroidTVChannel(host: host, port: 6467, identity: identity) else { return }
        pairing = channel
        pairStep = .request
        channel.onReady = { [weak self] in
            guard let self else { return }
            let request = PB.field(1, 2)
                + PB.field(2, 200)
                + PB.field(10, bytes: PB.field(1, string: "androidtvremote") + PB.field(2, string: "Tivu"))
            self.pairing?.send(request)
        }
        channel.onMessage = { [weak self] body in self?.pairingMessage(PBMessage(body)) }
        channel.onClose = { [weak self] reason in
            guard let self, self.pairing === channel else { return }
            self.onLog?("pairing channel: \(reason)")
            self.disconnect()
        }
        channel.start()
    }

    private func pairingMessage(_ message: PBMessage) {
        let status = message.int(2) ?? 0
        guard status == 200 else {
            onLog?("pairing refused: status \(status)")
            disconnect()
            return
        }
        let encoding = PB.field(1, 3) + PB.field(2, 6)           // esadecimale, 6 caratteri
        switch pairStep {
        case .request where message.has(11):
            pairStep = .options
            let options = PB.field(1, bytes: encoding) + PB.field(2, bytes: encoding) + PB.field(3, 1)
            pairing?.send(envelope(20, options))
        case .options where message.has(20):
            pairStep = .configuration
            let configuration = PB.field(1, bytes: encoding) + PB.field(2, 1)   // ruolo: ingresso
            pairing?.send(envelope(30, configuration))
        case .configuration where message.has(31):
            // La TV mostra il codice: il tempo di leggerlo non deve far scadere il tentativo.
            pairStep = .waitingForCode
            connectTimeout?.invalidate(); connectTimeout = nil
            state = .pairing
        case .secret where message.has(41):
            onLog?("paired")
            pairing?.cancel(); pairing = nil
            pairStep = .idle
            onClientKey?(Self.pairedMarker)
            state = .connecting
            armTimeout()
            openRemote()
        default:
            break
        }
    }

    private func envelope(_ field: Int, _ body: [UInt8]) -> [UInt8] {
        PB.field(1, 2) + PB.field(2, 200) + PB.field(field, bytes: body)
    }

    /// Il codice a 6 caratteri mostrato dalla TV. Restituisce false se non può essere quello giusto.
    @discardableResult
    public func submitPairingCode(_ text: String) -> Bool {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard pairStep == .waitingForCode, code.count == 6,
              let first = UInt8(code.prefix(2), radix: 16),
              let b = UInt8(code.dropFirst(2).prefix(2), radix: 16),
              let c = UInt8(code.dropFirst(4), radix: 16),
              let identity, let channel = pairing, let serverKey = channel.serverKey,
              let ownKey = ownPublicKey(identity),
              let own = AndroidTVIdentity.rsaParts(of: ownKey),
              let theirs = AndroidTVIdentity.rsaParts(of: serverKey) else { return false }
        var hash = SHA256()
        hash.update(data: Data(own.modulus))
        hash.update(data: Data(own.exponent))
        hash.update(data: Data(theirs.modulus))
        hash.update(data: Data(theirs.exponent))
        hash.update(data: Data([b, c]))
        let digest = Array(hash.finalize())
        // Il primo byte del codice è un controllo: se non torna, il codice è sbagliato e non vale la pena mandarlo.
        guard digest[0] == first else { onLog?("pairing code mismatch"); return false }
        pairStep = .secret
        channel.send(envelope(40, PB.field(1, bytes: digest)))
        return true
    }

    private func ownPublicKey(_ identity: SecIdentity) -> SecKey? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return nil }
        return SecCertificateCopyKey(certificate)
    }

    // MARK: - Telecomando (porta 6466)

    private func openRemote() {
        guard let identity, let channel = AndroidTVChannel(host: host, port: 6466, identity: identity) else { return }
        remote = channel
        channel.onMessage = { [weak self] body in self?.remoteMessage(PBMessage(body)) }
        channel.onClose = { [weak self] reason in
            guard let self, self.remote === channel else { return }
            self.onLog?("remote channel: \(reason)")
            // Collegamento chiuso subito dopo l'handshake, mai arrivato in funzione: la TV non ci riconosce.
            let rejected = self.state == .connecting && reason.contains("closed")
            self.disconnect()
            if rejected { self.onKeyRejected?() }
        }
        channel.start()
    }

    private func remoteMessage(_ message: PBMessage) {
        if let configure = message.message(1) {
            if let info = configure.message(2) { model = info.string(1) ?? model }
            let device = PB.field(1, string: "Tivu") + PB.field(2, string: "Tivu") + PB.field(3, 1)
                + PB.field(4, string: "1") + PB.field(5, string: "tivu.remote") + PB.field(6, string: "1.0.0")
            remote?.send(PB.field(1, bytes: PB.field(1, 622) + PB.field(2, bytes: device)))
        } else if message.has(2) {
            remote?.send(PB.field(2, bytes: PB.field(1, 622)))
        } else if let start = message.message(40) {
            connectTimeout?.invalidate(); connectTimeout = nil
            awake = (start.int(1) ?? 1) != 0
            state = .connected
            onAwake?(awake)
        } else if let ping = message.message(8) {
            remote?.send(PB.field(9, bytes: PB.field(1, ping.int(1) ?? 0)))
        } else if let volume = message.message(50) {
            levelMax = volume.int(6) ?? levelMax
            level = volume.int(7) ?? level
            muted = (volume.int(8) ?? 0) != 0
            onVolume?(percent(level), muted)
        } else if let inject = message.message(20), let app = inject.message(1)?.string(12), !app.isEmpty {
            onForegroundApp?(app)
        } else if message.has(3) {
            onLog?("remote error")
        }
    }

    private func percent(_ level: Int) -> Int {
        guard levelMax > 0 else { return level }
        return Int((Double(level) * 100 / Double(levelMax)).rounded())
    }

    private func key(_ code: Int, _ direction: Int = 3) {
        guard state == .connected else { return }
        remote?.send(PB.field(10, bytes: PB.field(1, code) + PB.field(2, direction)))
    }

    // MARK: - Comandi

    /// Un "imposta volume" non esiste: si arriva al valore con i tasti volume, a passi.
    public func setVolume(_ volume: Int) {
        let target = levelMax > 0 ? Int((Double(max(0, min(100, volume))) * Double(levelMax) / 100).rounded()) : volume
        let delta = target - level
        guard delta != 0 else { return }
        for _ in 0..<min(abs(delta), 20) { key(delta > 0 ? Key.volumeUp : Key.volumeDown) }
        level += max(-20, min(20, delta))
    }

    public func volumeUp() { key(Key.volumeUp) }
    public func volumeDown() { key(Key.volumeDown) }

    public func setMute(_ muted: Bool) {
        guard muted != self.muted else { return }
        self.muted = muted
        key(Key.mute)
    }

    public func switchInput(_ id: String) {
        let parts = id.split(separator: "_")
        guard parts.count == 2, let n = Int(parts[1]), (1...4).contains(n) else { return }
        key(Key.hdmi1 + n - 1)
    }

    /// Spegne (standby) se accesa.
    public func turnOff() { if awake { key(Key.power) } }

    /// Accende dallo standby con il collegamento ancora aperto.
    public func wake() { if !awake { key(Key.power) } }

    public func press(_ button: TVButton) {
        switch button {
        case .up: key(Key.up)
        case .down: key(Key.down)
        case .left: key(Key.left)
        case .right: key(Key.right)
        case .enter: key(Key.enter)
        case .back: key(Key.back)
        case .home: key(Key.home)
        case .menu: key(Key.menu)
        case .exit: key(Key.escape)
        }
    }

    /// La TV non dice quali ingressi ha: ci sono i tasti da HDMI 1 a HDMI 4, non quelli collegati.
    public func inputs(_ completion: @escaping ([TVInput]) -> Void) {
        completion((1...4).map { TVInput(id: "HDMI_\($0)", label: "HDMI\($0)", appId: "", connected: true) })
    }

    public func modelName(_ completion: @escaping (String?) -> Void) {
        completion(model.isEmpty ? nil : model)
    }
}
