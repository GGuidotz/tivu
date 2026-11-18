// L'identità con cui Tivu si presenta a una TV Android: un certificato autofirmato, creato la prima volta e tenuto
// nella cartella dell'app (Application Support/Tivu). La TV, dopo l'abbinamento con il codice, riconosce il Mac da lì.
// Il certificato si crea con openssl di sistema (/usr/bin/openssl). Da macOS 15 si carica solo in memoria; su
// macOS 14 il sistema lo tiene nel portachiavi di accesso. Solo Foundation e Security.

import Foundation
import Security

enum AndroidTVIdentity {
    private static let passphrase = "tivu"

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tivu", isDirectory: true)
    }

    private static var file: URL { folder.appendingPathComponent("android-tv-client.p12") }

    /// Un abbinamento fatto con una vecchia identità non vale più se il file sparisce: l'app lo capisce dal fatto che
    /// questa funzione crea una identità nuova (`created`).
    static func load(created: inout Bool) -> SecIdentity? {
        if !FileManager.default.fileExists(atPath: file.path) {
            guard generate() else { return nil }
            created = true
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        var options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
        // Da macOS 15 si carica solo in memoria; su macOS 14 il sistema la tiene nel portachiavi di accesso.
        if #available(macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let identity = first[kSecImportItemIdentity as String] else { return nil }
        return (identity as! SecIdentity)
    }

    /// Dimentica l'identità: il prossimo abbinamento ne crea una nuova.
    static func forget() {
        try? FileManager.default.removeItem(at: file)
    }

    private static func generate() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let work = fm.temporaryDirectory.appendingPathComponent("tivu-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return false }
        defer { try? fm.removeItem(at: work) }
        let key = work.appendingPathComponent("key.pem").path
        let cert = work.appendingPathComponent("cert.pem").path
        let pfx = work.appendingPathComponent("id.p12").path
        guard run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                   "-days", "7300", "-subj", "/CN=Tivu"]),
              run(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", pfx, "-passout", "pass:\(passphrase)"]),
              let data = try? Data(contentsOf: URL(fileURLWithPath: pfx)) else { return false }
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }

    private static func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Chiavi pubbliche

    /// Modulo ed esponente di una chiave RSA, senza zeri iniziali: servono al codice di abbinamento.
    static func rsaParts(of key: SecKey) -> (modulus: [UInt8], exponent: [UInt8])? {
        guard let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        guard let sequence = readTag(bytes, &i, 0x30), sequence >= 0,
              let n = readTag(bytes, &i, 0x02), i + n <= bytes.count else { return nil }
        let modulus = Array(bytes[i..<(i + n)]); i += n
        guard let e = readTag(bytes, &i, 0x02), i + e <= bytes.count else { return nil }
        let exponent = Array(bytes[i..<(i + e)])
        func strip(_ v: [UInt8]) -> [UInt8] { Array(v.drop(while: { $0 == 0 })) }
        return (strip(modulus), strip(exponent))
    }

    /// Legge l'etichetta DER attesa e restituisce la lunghezza del contenuto; `i` avanza al contenuto.
    private static func readTag(_ b: [UInt8], _ i: inout Int, _ tag: UInt8) -> Int? {
        guard i < b.count, b[i] == tag else { return nil }
        i += 1
        guard i < b.count else { return nil }
        var length = Int(b[i]); i += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 3, i + count <= b.count else { return nil }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(b[i]); i += 1 }
        }
        return length
    }
}
