// Trova le TV LG con webOS nella rete di casa (SSDP: una domanda a tutti, risponde chi è una TV), ne legge nome e
// modello, e l'indirizzo fisico della scheda di rete, che serve per accenderla da spenta (Wake-on-LAN).
// Solo Foundation e socket di sistema. Niente resta in ascolto: una ricerca dura tre secondi, solo quando la chiedi.

import Foundation

public struct DiscoveredTV: Equatable, Identifiable {
    public let host: String        // indirizzo nella rete di casa
    public var name: String        // "[LG] webOS TV"
    public var model: String       // "42XX650V-ZN"
    public var mac: String?        // "aa:bb:cc:dd:ee:ff"
    public var id: String { host }
}

public enum TVDiscovery {
    /// Cerca per `seconds` secondi; il risultato arriva sul thread principale.
    public static func search(seconds: Double = 3, completion: @escaping ([DiscoveredTV]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [DiscoveredTV] = []
            for (host, location) in probe(seconds: seconds) {
                var tv = DiscoveredTV(host: host, name: "LG TV", model: "", mac: macAddress(of: host))
                if let location, let xml = fetch(location) {
                    tv.name = tag("friendlyName", in: xml) ?? tv.name
                    // Il modello vero è una sigla lunga; alcune descrizioni dicono solo "1.0".
                    let model = tag("modelNumber", in: xml) ?? ""
                    tv.model = model.count > 4 ? model : ""
                }
                found.append(tv)
            }
            // Con il firewall di macOS acceso le risposte a quella domanda non arrivano alle app non firmate da Apple:
            // allora si bussa alla porta delle TV webOS su ogni indirizzo della rete di casa (collegamenti in uscita,
            // che il firewall lascia passare).
            if found.isEmpty {
                found = scan().map { DiscoveredTV(host: $0, name: "LG TV", model: "", mac: macAddress(of: $0)) }
            }
            found.sort { $0.host.compare($1.host, options: .numeric) == .orderedAscending }
            DispatchQueue.main.async { completion(found) }
        }
    }

    /// Indirizzo → posizione della descrizione (se la risposta la dice).
    private static func probe(seconds: Double) -> [(String, URL?)] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var wait = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var group = sockaddr_in()
        group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &group.sin_addr)
        // Il servizio delle TV webOS e, per i modelli che non lo annunciano, il loro nome generico.
        for target in ["urn:lge-com:service:webos-second-screen:1", "urn:dial-multiscreen-org:service:dial:1"] {
            let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
            let bytes = Array(message.utf8)
            withUnsafePointer(to: &group) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var hosts: [String: URL?] = [:]
        var order: [String] = []
        let deadline = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard n > 0 else { continue }
            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            let lower = text.lowercased()
            guard lower.contains("webos") || lower.contains("lg smart tv") || lower.contains("lge") else { continue }
            var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &name, socklen_t(INET_ADDRSTRLEN))
            let host = String(cString: name)
            let location = header("location", in: text).flatMap { URL(string: $0) }
            if hosts[host] == nil { order.append(host) }
            // La descrizione con il modello è quella del servizio "LG Smart TV"; le altre vanno bene se manca.
            if lower.contains("lg smart tv") || (hosts[host] ?? nil) == nil { hosts[host] = location }
        }
        return order.map { ($0, hosts[$0] ?? nil) }
    }

    // MARK: - Scansione

    /// Gli indirizzi della rete di casa con aperte tutte e due le porte delle TV webOS (3000 e 3001).
    private static func scan() -> [String] {
        var candidates: [UInt32] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var cursor = list
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = Int32(item.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let address = item.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = item.pointee.ifa_netmask else { continue }
            let ip = UInt32(bigEndian: address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr })
            let mask = UInt32(bigEndian: netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr })
            // Solo reti private e piccole (di casa): al massimo 1022 indirizzi.
            let isPrivate = ip >> 24 == 10 || ip >> 20 == 0xAC1 || ip >> 16 == 0xC0A8
            guard isPrivate, mask >= 0xFFFF_FC00, mask != 0xFFFF_FFFF else { continue }
            let network = ip & mask, broadcast = network | ~mask
            guard broadcast - network >= 2 else { continue }
            for host in (network + 1)..<broadcast where host != ip { candidates.append(host) }
        }
        let open = reachable(Array(Set(candidates)), port: 3000)
        return reachable(open, port: 3001).map { host in
            var address = in_addr(s_addr: host.bigEndian)
            var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &address, &name, socklen_t(INET_ADDRSTRLEN))
            return String(cString: name)
        }
    }

    /// Quali indirizzi accettano un collegamento sulla porta, provati tutti insieme: in tutto meno di un secondo.
    private static func reachable(_ hosts: [UInt32], port: UInt16) -> [UInt32] {
        var result: [UInt32] = []
        for start in stride(from: 0, to: hosts.count, by: 200) {
            let batch = Array(hosts[start..<min(start + 200, hosts.count)])
            var sockets: [pollfd] = []
            var owners: [UInt32] = []
            for host in batch {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian
                address.sin_addr.s_addr = host.bigEndian
                let r = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if r == 0 || errno == EINPROGRESS {
                    sockets.append(pollfd(fd: fd, events: Int16(POLLOUT), revents: 0))
                    owners.append(host)
                } else {
                    close(fd)
                }
            }
            let deadline = Date().addingTimeInterval(0.7)
            var done = Set<Int>()
            while done.count < sockets.count {
                let left = deadline.timeIntervalSinceNow
                guard left > 0, poll(&sockets, nfds_t(sockets.count), Int32(left * 1000)) > 0 else { break }
                for i in sockets.indices where !done.contains(i) && sockets[i].revents != 0 {
                    done.insert(i)
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(sockets[i].fd, SOL_SOCKET, SO_ERROR, &error, &length)
                    if error == 0, sockets[i].revents & Int16(POLLOUT) != 0 { result.append(owners[i]) }
                    sockets[i].events = 0
                }
            }
            sockets.forEach { close($0.fd) }
        }
        return result
    }

    private static func header(_ name: String, in response: String) -> String? {
        for line in response.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == name {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func fetch(_ url: URL) -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let done = DispatchSemaphore(value: 0)
        var text: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { text = String(decoding: data, as: UTF8.self) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return text
    }

    private static func tag(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// L'indirizzo fisico di un dispositivo con cui il Mac ha appena parlato (tabella ARP del sistema).
    public static func macAddress(of host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let at = text.range(of: " at ") else { return nil }
        let word = text[at.upperBound...].split(separator: " ").first.map(String.init) ?? ""
        let parts = word.split(separator: ":")
        guard parts.count == 6, parts.allSatisfy({ UInt8($0, radix: 16) != nil }) else { return nil }
        return parts.map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":")
    }
}

/// Accende la TV da spenta: un "pacchetto magico" con il suo indirizzo fisico, mandato a tutta la rete di casa.
/// Funziona se sulla TV è accesa l'opzione per l'accensione dalla rete (di solito in Generale o Rete).
public enum WakeOnLAN {
    @discardableResult
    public static func wake(mac: String) -> Bool {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return false }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var sent = false
        for port in [UInt16(9), 7] {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = INADDR_BROADCAST
            let n = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if n == packet.count { sent = true }
        }
        return sent
    }
}
