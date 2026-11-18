// Il minimo di Protocol Buffers che serve al telecomando delle TV Android: campi con numero, interi variabili e
// blocchi di byte. Niente libreria esterna: i messaggi sono pochi e piccoli. Solo Foundation.

import Foundation

enum PB {
    static func varint(_ value: UInt64) -> [UInt8] {
        var out: [UInt8] = []
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    /// Campo intero (anche bool ed enum).
    static func field(_ number: Int, _ value: Int) -> [UInt8] {
        varint(UInt64(number << 3)) + varint(UInt64(bitPattern: Int64(value)))
    }

    /// Campo a blocco: testo, byte o messaggio annidato.
    static func field(_ number: Int, bytes: [UInt8]) -> [UInt8] {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
    }

    static func field(_ number: Int, string: String) -> [UInt8] {
        field(number, bytes: Array(string.utf8))
    }

    /// Un messaggio preceduto dalla sua lunghezza: così viaggia sul collegamento con la TV.
    static func framed(_ body: [UInt8]) -> [UInt8] {
        varint(UInt64(body.count)) + body
    }
}

/// Un messaggio letto: i campi per numero.
struct PBMessage {
    private var ints: [Int: Int64] = [:]
    private var blocks: [Int: [UInt8]] = [:]

    init(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            guard let (tag, next) = Self.readVarint(bytes, i) else { return }
            i = next
            let number = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                guard let (v, n) = Self.readVarint(bytes, i) else { return }
                ints[number] = Int64(bitPattern: v)
                i = n
            case 2:
                guard let (length, n) = Self.readVarint(bytes, i), n + Int(length) <= bytes.count else { return }
                blocks[number] = Array(bytes[n..<(n + Int(length))])
                i = n + Int(length)
            case 1: i += 8
            case 5: i += 4
            default: return
            }
        }
    }

    func int(_ number: Int) -> Int? { ints[number].map { Int($0) } }
    func has(_ number: Int) -> Bool { ints[number] != nil || blocks[number] != nil }
    func bytes(_ number: Int) -> [UInt8]? { blocks[number] }
    func message(_ number: Int) -> PBMessage? { blocks[number].map(PBMessage.init) }
    func string(_ number: Int) -> String? { blocks[number].map { String(decoding: $0, as: UTF8.self) } }

    private static func readVarint(_ bytes: [UInt8], _ start: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < bytes.count, shift < 64 {
            let b = bytes[i]
            result |= UInt64(b & 0x7F) << shift
            i += 1
            if b & 0x80 == 0 { return (result, i) }
            shift += 7
        }
        return nil
    }

    /// La lunghezza all'inizio di un flusso di messaggi, se c'è già tutta: (lunghezza, byte occupati dalla lunghezza).
    static func frameHeader(_ bytes: [UInt8]) -> (length: Int, header: Int)? {
        guard let (length, next) = readVarint(bytes, 0), length < 1 << 20 else { return nil }
        return (Int(length), next)
    }
}
