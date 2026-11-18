// Un collegamento TLS con una TV Android: messaggi preceduti dalla lunghezza, con il certificato di Tivu come
// identità. La TV ha un certificato autofirmato: non si verifica la catena, ma se ne conserva la chiave pubblica,
// che entra nel codice di abbinamento. Tutto sul thread principale. Solo Foundation, Network e Security.

import Foundation
import Network
import Security

final class AndroidTVChannel {
    var onReady: (() -> Void)?
    var onMessage: (([UInt8]) -> Void)?
    var onClose: ((String) -> Void)?
    /// La chiave pubblica della TV, letta dal suo certificato durante l'handshake.
    private(set) var serverKey: SecKey?

    private let connection: NWConnection
    private var buffer: [UInt8] = []
    private var closed = false

    init?(host: String, port: UInt16, identity: SecIdentity) {
        guard let nwPort = NWEndpoint.Port(rawValue: port), let secIdentity = sec_identity_create(identity) else { return nil }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        let box = KeyBox()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { metadata, _, complete in
            sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
                if box.key == nil {
                    box.key = SecCertificateCopyKey(sec_certificate_copy_ref(certificate).takeRetainedValue())
                }
            }
            complete(true)
        }, .main)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: NWParameters(tls: tls, tcp: tcp))
        self.box = box
    }

    private final class KeyBox { var key: SecKey? }
    private var box: KeyBox

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                self.serverKey = self.box.key
                self.onReady?()
                self.receive()
            case .failed(let error):
                self.finish("failed: \(error)")
            case .waiting(let error):
                // Indirizzo che non risponde (TV spenta o altra rete): non si aspetta, lo decide chi chiama.
                self.finish("waiting: \(error)")
            case .cancelled:
                self.finish("cancelled")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    func send(_ body: [UInt8]) {
        guard !closed else { return }
        connection.send(content: Data(PB.framed(body)), completion: .contentProcessed { [weak self] error in
            if let error { self?.finish("send failed: \(error)") }
        })
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func finish(_ reason: String) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?(reason)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(contentsOf: data)
                self.drain()
            }
            if let error {
                self.finish("receive failed: \(error)")
            } else if isComplete {
                self.finish("closed by the TV")
            } else if !self.closed {
                self.receive()
            }
        }
    }

    private func drain() {
        while let (length, header) = PBMessage.frameHeader(buffer), buffer.count >= header + length {
            let body = Array(buffer[header..<(header + length)])
            buffer.removeFirst(header + length)
            onMessage?(body)
            if closed { return }
        }
    }
}
