// La chiave di abbinamento della TV sta nel Portachiavi, non nelle preferenze: chi la ha controlla la TV.
// Una voce sola (password generica, servizio = identificativo dell'app), leggibile solo dopo il primo sblocco del Mac
// e mai copiata su altri dispositivi.

import Foundation
import Security

enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "local.tivu.app"
    private static let account = "clientKey"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Salva la chiave (la voce vecchia viene sostituita); con nil la cancella. Dice se è andata a buon fine.
    @discardableResult
    static func save(_ value: String?) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard let value else { return true }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
