// Ciò che l'app chiede a una TV, qualunque sia il suo sistema: LG webOS (TVClient) o Android TV / Google TV
// (AndroidTVClient). Ognuna parla il proprio protocollo di rete; l'app vede solo questa interfaccia.
// Solo Foundation; tutte le chiamate e le risposte sul thread principale.

import Foundation

/// Il sistema della TV.
public enum TVBrand: String, Codable, CaseIterable {
    case lg, android

    /// "LG", "Android TV": per il titolo del pannello quando la TV non dice il proprio nome.
    public var label: String {
        switch self {
        case .lg: return "LG"
        case .android: return "Android TV"
        }
    }
}

public protocol TVController: AnyObject {
    var state: TVState { get }
    var onState: ((TVState) -> Void)? { get set }
    var onVolume: ((_ volume: Int, _ muted: Bool) -> Void)? { get set }
    var onForegroundApp: ((String) -> Void)? { get set }
    /// Il segno dell'abbinamento da salvare per le volte dopo (la chiave di webOS; su Android un semplice marcatore).
    var onClientKey: ((String) -> Void)? { get set }
    /// La TV non riconosce più l'abbinamento salvato (per esempio dopo un ripristino): va dimenticato.
    var onKeyRejected: (() -> Void)? { get set }
    var onLog: ((String) -> Void)? { get set }

    func connect(host: String, clientKey: String?)
    func disconnect()

    func setVolume(_ volume: Int)
    func volumeUp()
    func volumeDown()
    func setMute(_ muted: Bool)
    func switchInput(_ id: String)
    func turnOff()
    func press(_ button: TVButton)

    func inputs(_ completion: @escaping ([TVInput]) -> Void)
    func modelName(_ completion: @escaping (String?) -> Void)
}
