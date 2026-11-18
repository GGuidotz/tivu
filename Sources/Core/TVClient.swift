// Il collegamento con la TV: il protocollo di rete dei televisori LG con webOS (SSAP, un WebSocket: cifrato sulla
// porta 3001 quando la TV lo permette, in chiaro sulla 3000 per le TV vecchie).
// Il cavo HDMI porta solo immagine e suono: macOS non parla HDMI-CEC, quindi volume, ingressi e spegnimento passano
// dalla rete di casa. La prima volta la TV chiede di accettare il collegamento con il telecomando e dà una chiave,
// che resta sul Mac (nel Portachiavi). Solo Foundation, Security e CryptoKit; tutte le chiamate e le risposte sul thread principale.

import CryptoKit
import Foundation
import Security

public struct TVInput: Equatable, Identifiable {
    public let id: String        // "HDMI_1"
    public let label: String     // "HDMI1"
    public let appId: String     // "com.webos.app.hdmi1": l'app in primo piano quando l'ingresso è scelto
    public let connected: Bool

    /// "HDMI 1": il nome della presa, che non cambia se sulla TV dai un'etichetta all'ingresso.
    public var title: String {
        let parts = id.split(separator: "_")
        if parts.count == 2, parts[0].uppercased() == "HDMI", Int(parts[1]) != nil { return "HDMI \(parts[1])" }
        return label
    }
}

public enum TVState: Equatable {
    case disconnected
    case connecting
    /// La TV mostra la richiesta: va accettata con il telecomando.
    case pairing
    case connected
}

/// I tasti del telecomando che la TV accetta dalla rete.
public enum TVButton: String, CaseIterable {
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", enter = "ENTER"
    case back = "BACK", home = "HOME", menu = "MENU", exit = "EXIT"
}

public final class TVClient: NSObject, URLSessionWebSocketDelegate, TVController {
    public private(set) var state = TVState.disconnected { didSet { if state != oldValue { onState?(state) } } }
    public var onState: ((TVState) -> Void)?
    public var onVolume: ((_ volume: Int, _ muted: Bool) -> Void)?
    public var onForegroundApp: ((String) -> Void)?
    /// La chiave data dalla TV dopo che hai accettato: da salvare per le volte dopo.
    public var onClientKey: ((String) -> Void)?
    /// La TV ha rifiutato la chiave salvata (per esempio dopo un ripristino): va dimenticata.
    public var onKeyRejected: (() -> Void)?
    public var onLog: ((String) -> Void)?

    /// L'impronta (SHA-256, esadecimale) del certificato della TV, fissata al primo collegamento cifrato riuscito.
    /// Chi usa il client la imposta prima di connect(): se c'è, il certificato della TV deve coincidere.
    public var pinnedFingerprint: String?
    /// Primo collegamento cifrato riuscito (fiducia al primo uso): l'impronta da salvare per le volte dopo.
    public var onFingerprint: ((String) -> Void)?
    /// Il certificato della TV non è quello fissato: nessun dato è stato inviato, e non si ricade sul collegamento in chiaro.
    public var onCertificateChanged: (() -> Void)?
    /// Il collegamento in corso è cifrato (wss) e non in chiaro (ws).
    public private(set) var isSecure = false

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var pointerOpening = false
    private var pendingButtons: [TVButton] = []
    private var nextId = 0
    private var waiting: [String: ([String: Any]?) -> Void] = [:]
    private var subscriptions: [String: ([String: Any]) -> Void] = [:]
    private var keepAlive: Timer?
    private var connectTimeout: Timer?
    private var sentKey = false
    private var connectHost = ""
    private var connectKey: String?
    /// Impronta vista in questo tentativo, ancora da fissare: si salva solo quando la TV ha accettato la registrazione.
    private var seenFingerprint: String?
    private var certificateMismatch = false

    private static let permissions = [
        "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_MEDIA_RECORDING", "CONTROL_INPUT_TEXT", "CONTROL_INPUT_TV",
        "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_POWER", "READ_APP_STATUS", "READ_CURRENT_CHANNEL",
        "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE", "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST",
        "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE", "READ_INSTALLED_APPS", "READ_SETTINGS", "WRITE_SETTINGS",
    ]

    public override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Collegamento

    public func connect(host: String, clientKey: String?) {
        disconnect()
        state = .connecting
        sentKey = clientKey != nil
        connectHost = host
        connectKey = clientKey
        seenFingerprint = nil
        certificateMismatch = false
        // Prima il collegamento cifrato (wss, porta 3001); se la TV non lo offre si ricade su ws (porta 3000).
        guard openSocket(secure: true) else { state = .disconnected; return }
        // TV spenta: l'indirizzo non risponde e il tentativo resterebbe appeso a lungo.
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, self.state == .connecting else { return }
            self.onLog?("connect timed out")
            self.disconnect()
        }
        RunLoop.main.add(timer, forMode: .common)
        connectTimeout = timer
    }

    /// Apre il WebSocket e invia la registrazione (con la chiave, se c'è). I dati partono solo a collegamento stabilito:
    /// con wss, se il certificato non è accettato dal delegato la connessione cade prima di inviare la chiave.
    private func openSocket(secure: Bool) -> Bool {
        guard let url = URL(string: secure ? "wss://\(connectHost):3001" : "ws://\(connectHost):3000") else { return false }
        isSecure = secure
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task)
        var payload: [String: Any] = [
            "pairingType": "PROMPT",
            "manifest": ["manifestVersion": 1, "permissions": Self.permissions] as [String: Any],
        ]
        if let connectKey { payload["client-key"] = connectKey }
        send(["type": "register", "id": "register", "payload": payload], on: task)
        return true
    }

    public func disconnect() {
        connectTimeout?.invalidate(); connectTimeout = nil
        keepAlive?.invalidate(); keepAlive = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        pointer?.cancel(with: .goingAway, reason: nil); pointer = nil
        pointerOpening = false
        pendingButtons = []
        let lost = waiting
        waiting = [:]
        subscriptions = [:]
        state = .disconnected
        lost.values.forEach { $0(nil) }
    }

    private func didRegister() {
        connectTimeout?.invalidate(); connectTimeout = nil
        // Fiducia al primo uso: la TV ha accettato, quindi il suo certificato è quello giusto. Da ora deve coincidere.
        if isSecure, pinnedFingerprint == nil, let fingerprint = seenFingerprint {
            pinnedFingerprint = fingerprint
            onFingerprint?(fingerprint)
        }
        onLog?(isSecure ? "connected over wss" : "connected over plain ws (TV without wss)")
        state = .connected
        // Un collegamento fermo viene chiuso dopo un minuto: una lettura leggera ogni 25 s lo tiene vivo e si accorge
        // subito se la TV è stata spenta.
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
            self?.request("ssap://audio/getVolume") { [weak self] reply in
                if reply == nil, self?.state == .connected { self?.disconnect() }
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        keepAlive = timer
        subscribe("ssap://audio/getVolume") { [weak self] p in
            guard let self else { return }
            // Le versioni nuove di webOS mettono i valori dentro "volumeStatus" e chiamano il muto "muteStatus".
            let v = (p["volumeStatus"] as? [String: Any]) ?? p
            guard let volume = (v["volume"] as? NSNumber)?.intValue else { return }
            let muted = (v["muted"] as? Bool) ?? (v["mute"] as? Bool) ?? (v["muteStatus"] as? Bool) ?? false
            self.onVolume?(volume, muted)
        }
        subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo") { [weak self] p in
            if let app = p["appId"] as? String { self?.onForegroundApp?(app) }
        }
    }

    // MARK: - Comandi

    public func setVolume(_ volume: Int) { request("ssap://audio/setVolume", ["volume": max(0, min(100, volume))]) }
    public func volumeUp() { request("ssap://audio/volumeUp") }
    public func volumeDown() { request("ssap://audio/volumeDown") }
    public func setMute(_ muted: Bool) { request("ssap://audio/setMute", ["mute": muted]) }
    public func switchInput(_ id: String) { request("ssap://tv/switchInput", ["inputId": id]) }
    public func turnOff() { request("ssap://system/turnOff") }

    public func inputs(_ completion: @escaping ([TVInput]) -> Void) {
        request("ssap://tv/getExternalInputList") { reply in
            let devices = reply?["devices"] as? [[String: Any]] ?? []
            completion(devices.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return TVInput(id: id, label: d["label"] as? String ?? id, appId: d["appId"] as? String ?? "",
                               connected: d["connected"] as? Bool ?? false)
            })
        }
    }

    /// Il modello, come lo dice la TV ("42XX650V-ZN").
    public func modelName(_ completion: @escaping (String?) -> Void) {
        request("ssap://system/getSystemInfo") { completion($0?["modelName"] as? String) }
    }

    /// Una richiesta: la risposta (o nil se la TV non c'è o dice di no) arriva sul thread principale.
    public func request(_ uri: String, _ payload: [String: Any]? = nil, completion: (([String: Any]?) -> Void)? = nil) {
        guard let socket, state == .connected else { completion?(nil); return }
        nextId += 1
        let id = "r\(nextId)"
        var message: [String: Any] = ["type": "request", "id": id, "uri": uri]
        if let payload { message["payload"] = payload }
        if let completion { waiting[id] = completion }
        send(message, on: socket)
    }

    private func subscribe(_ uri: String, _ handler: @escaping ([String: Any]) -> Void) {
        guard let socket else { return }
        nextId += 1
        let id = "s\(nextId)"
        subscriptions[id] = handler
        send(["type": "subscribe", "id": id, "uri": uri], on: socket)
    }

    // MARK: - Telecomando

    /// Un tasto del telecomando. Passa da un secondo collegamento, che la TV apre su richiesta e si tiene finché serve.
    public func press(_ button: TVButton) {
        guard state == .connected else { return }
        if let pointer {
            sendButton(button, on: pointer)
            return
        }
        pendingButtons.append(button)
        guard !pointerOpening else { return }
        pointerOpening = true
        request("ssap://com.webos.service.networkinput/getPointerInputSocket") { [weak self] reply in
            guard let self else { return }
            self.pointerOpening = false
            guard let path = reply?["socketPath"] as? String, let url = URL(string: path) else {
                self.pendingButtons = []
                return
            }
            let task = self.session.webSocketTask(with: url)
            self.pointer = task
            task.resume()
            self.receive(on: task)
            let queued = self.pendingButtons
            self.pendingButtons = []
            queued.forEach { self.sendButton($0, on: task) }
        }
    }

    private func sendButton(_ button: TVButton, on task: URLSessionWebSocketTask) {
        task.send(.string("type:button\nname:\(button.rawValue)\n\n")) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { if self?.pointer === task { self?.pointer = nil } }
        }
    }

    // MARK: - Messaggi

    private func send(_ message: [String: Any], on task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async { self?.failed(task, error) }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.failed(task, error)
                case .success(let message):
                    if task === self.socket, case .string(let text) = message { self.handle(text) }
                    if task === self.socket || task === self.pointer { self.receive(on: task) }
                }
            }
        }
    }

    private func failed(_ task: URLSessionWebSocketTask, _ error: Error) {
        if task === pointer {
            pointer = nil
        } else if task === socket {
            if certificateMismatch {
                // Certificato diverso da quello fissato: errore chiaro, niente ricaduta su ws.
                onLog?("TV certificate does not match the pinned one")
                disconnect()
                onCertificateChanged?()
                return
            }
            if isSecure, state == .connecting {
                if pinnedFingerprint != nil {
                    // La TV è già stata vista con wss: se ora non risponde, ws in chiaro sarebbe un passo indietro.
                    onLog?("wss unavailable but the TV was pinned: not falling back to ws")
                    disconnect()
                } else if !openSocket(secure: false) {
                    disconnect()
                } else {
                    onLog?("wss unavailable: falling back to plain ws")
                }
                return
            }
            onLog?("socket closed: \((error as NSError).domain) \((error as NSError).code)")
            disconnect()
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = message["type"] as? String ?? ""
        let id = message["id"] as? String ?? ""
        let payload = message["payload"] as? [String: Any] ?? [:]
        switch type {
        case "registered":
            if let key = payload["client-key"] as? String { onClientKey?(key) }
            didRegister()
        case "response" where id == "register":
            // "Sto chiedendo all'utente": il tempo di prendere il telecomando non deve far scadere il tentativo.
            if payload["pairingType"] != nil {
                connectTimeout?.invalidate(); connectTimeout = nil
                state = .pairing
            }
        case "error" where id == "register":
            onLog?("register refused: \(message["error"] as? String ?? "?")")
            let hadKey = sentKey
            disconnect()
            if hadKey { onKeyRejected?() }
        case "response":
            if let handler = subscriptions[id] {
                handler(payload)
            } else if let done = waiting.removeValue(forKey: id) {
                done(payload)
            }
        case "error":
            subscriptions[id] = nil
            waiting.removeValue(forKey: id)?(nil)
        default:
            break
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    /// Il certificato della TV è autofirmato: lo si accetta solo se l'impronta SHA-256 del certificato foglia coincide
    /// con quella fissata (o, la prima volta, la si ricorda per dopo). Vale anche per il socket del puntatore.
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        if let pinned = pinnedFingerprint {
            if fingerprint == pinned {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                certificateMismatch = true
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            seenFingerprint = fingerprint
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if webSocketTask === pointer {
            pointer = nil
        } else if webSocketTask === socket {
            onLog?("socket closed by the TV (\(closeCode.rawValue))")
            disconnect()
        }
    }
}
