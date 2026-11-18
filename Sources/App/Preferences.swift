// Le scelte di chi usa l'app e la TV abbinata, salvate in UserDefaults (sul Mac, mai altrove).
// Predefiniti sensati: si usa senza toccare nulla.

import Foundation

/// Quando i tasti volume e muto della tastiera comandano la TV.
enum MediaKeysMode: String, CaseIterable, Codable, Identifiable {
    case hdmi, always, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hdmi: L("Quando l'audio del Mac esce dalla TV")
        case .always: L("Sempre, se la TV è accesa")
        case .never: L("Mai")
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet { Localization.language = language; save(language, "language") }
    }
    /// La guida dei primi passi è già stata vista.
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    @Published var mediaKeys: MediaKeysMode { didSet { save(mediaKeys, "mediaKeys") } }
    /// Il telecomando nel pannello: aperto o chiuso, come l'hai lasciato.
    @Published var showRemote: Bool { didSet { defaults.set(showRemote, forKey: "showRemote") } }

    // La TV abbinata.
    @Published var tvHost: String? { didSet { defaults.set(tvHost, forKey: "tvHost") } }
    @Published var tvName: String { didSet { defaults.set(tvName, forKey: "tvName") } }
    @Published var tvModel: String { didSet { defaults.set(tvModel, forKey: "tvModel") } }
    /// Il sistema della TV abbinata: LG webOS (predefinito, come nelle versioni precedenti) o Android TV.
    @Published var tvBrand: TVBrand { didSet { save(tvBrand, "tvBrand") } }
    /// L'indirizzo fisico della TV: serve per accenderla da spenta.
    @Published var tvMAC: String? { didSet { defaults.set(tvMAC, forKey: "tvMAC") } }
    /// La chiave data dalla TV quando hai accettato il collegamento: sta nel Portachiavi (Keychain.swift), non qui.
    @Published var clientKey: String? { didSet { Keychain.save(clientKey) } }
    /// L'impronta del certificato della TV, fissata al primo collegamento cifrato. Non è un segreto.
    @Published var tvCertFingerprint: String? { didSet { defaults.set(tvCertFingerprint, forKey: "tvCertFingerprint") } }

    init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        let d = UserDefaults.standard
        language = load("language", AppLanguage.system)
        onboardingDone = d.bool(forKey: "onboardingDone")
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        mediaKeys = load("mediaKeys", MediaKeysMode.hdmi)
        showRemote = d.bool(forKey: "showRemote")
        tvHost = d.string(forKey: "tvHost")
        tvName = d.string(forKey: "tvName") ?? ""
        tvModel = d.string(forKey: "tvModel") ?? ""
        tvBrand = load("tvBrand", TVBrand.lg)
        tvMAC = d.string(forKey: "tvMAC")
        // Dalla 0.1.0 la chiave stava nelle preferenze: si sposta nel Portachiavi e si toglie da qui.
        if let legacy = d.string(forKey: "clientKey") {
            if Keychain.read() != nil || Keychain.save(legacy) { d.removeObject(forKey: "clientKey") }
        }
        clientKey = Keychain.read() ?? d.string(forKey: "clientKey")
        tvCertFingerprint = d.string(forKey: "tvCertFingerprint")
        Localization.language = language
    }

    var hasTV: Bool { tvHost != nil }

    func forgetTV() {
        tvHost = nil; tvName = ""; tvModel = ""; tvMAC = nil; clientKey = nil; tvBrand = .lg; tvCertFingerprint = nil
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
