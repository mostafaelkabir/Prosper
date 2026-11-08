import Foundation

/// Reads the server name from the first bytes of a TLS connection (the
/// ClientHello's SNI extension). Chrome and Brave open their connections below
/// Network.framework, so the content filter gets no hostname for them; this is
/// how their flows get a name (PLAN.md §3.3).
///
/// Bounded and defensive: it never reads past the buffer, never allocates more
/// than the hostname, and gives up (nil) on anything that is not a well-formed
/// ClientHello.
public enum SNIParser {
    public enum Result: Equatable, Sendable {
        case hostname(String)
        /// A TLS ClientHello without a server name (rare: IP connections).
        case noServerName
        /// More bytes are needed: the record is split across packets.
        case needMoreData
        /// Not TLS at all.
        case notTLS
    }

    /// Largest ClientHello we wait for. Post-quantum key shares push Chrome's
    /// to ~1.8 KB, split across two TCP segments.
    public static let maxPeekBytes = 4096

    public static func parse(_ bytes: [UInt8]) -> Result {
        // TLS record header: type 22 (handshake), version 3.x, length.
        guard bytes.count >= 5 else { return bytes.isEmpty || bytes[0] == 0x16 ? .needMoreData : .notTLS }
        guard bytes[0] == 0x16, bytes[1] == 0x03 else { return .notTLS }
        let recordLength = Int(bytes[3]) << 8 | Int(bytes[4])
        let available = min(bytes.count, 5 + recordLength)

        var r = Reader(bytes: bytes, position: 5, end: available)
        // Handshake header: type 1 (ClientHello), 24-bit length.
        guard let handshakeType = r.u8() else { return .needMoreData }
        guard handshakeType == 0x01 else { return .notTLS }
        guard r.skip(3), r.skip(2 + 32) else { return incomplete(bytes, recordLength) } // length, version, random
        guard let sessionIDLength = r.u8(), r.skip(Int(sessionIDLength)) else { return incomplete(bytes, recordLength) }
        guard let cipherLength = r.u16(), r.skip(cipherLength) else { return incomplete(bytes, recordLength) }
        guard let compressionLength = r.u8(), r.skip(Int(compressionLength)) else { return incomplete(bytes, recordLength) }
        guard let extensionsLength = r.u16() else {
            return r.position >= available && available < 5 + recordLength ? .needMoreData : .noServerName
        }
        let extensionsEnd = min(r.position + extensionsLength, available)
        while r.position + 4 <= extensionsEnd {
            guard let type = r.u16(), let length = r.u16() else { break }
            if type == 0x0000 { // server_name
                var s = Reader(bytes: bytes, position: r.position, end: min(r.position + length, available))
                guard s.u16() != nil else { return incomplete(bytes, recordLength) } // list length
                guard let nameType = s.u8(), let nameLength = s.u16() else { return incomplete(bytes, recordLength) }
                guard nameType == 0 else { return .noServerName }
                guard let nameBytes = s.take(nameLength) else { return incomplete(bytes, recordLength) }
                guard let name = String(bytes: nameBytes, encoding: .ascii), isPlausibleHostname(name) else {
                    return .noServerName
                }
                return .hostname(name.lowercased())
            }
            guard r.skip(length) else { break }
        }
        return 5 + recordLength > bytes.count ? .needMoreData : .noServerName
    }

    private static func incomplete(_ bytes: [UInt8], _ recordLength: Int) -> Result {
        5 + recordLength > bytes.count ? .needMoreData : .notTLS
    }

    static func isPlausibleHostname(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 253 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private struct Reader {
        let bytes: [UInt8]
        var position: Int
        let end: Int

        mutating func u8() -> UInt8? {
            guard position < end else { return nil }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func u16() -> Int? {
            guard position + 2 <= end else { return nil }
            defer { position += 2 }
            return Int(bytes[position]) << 8 | Int(bytes[position + 1])
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, position + count <= end else { return false }
            position += count
            return true
        }

        mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard count >= 0, position + count <= end else { return nil }
            defer { position += count }
            return bytes[position..<position + count]
        }
    }
}
