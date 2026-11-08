import Foundation

/// Just enough DNS (RFC 1035) for the Mac's DNS proxy: read the question of a
/// query, read the address records of an answer, and write the three kinds of
/// reply the proxy makes itself — "no such domain", "no records", and a forced
/// SafeSearch address. Everything else is forwarded untouched.
public struct DNSQuestion: Equatable, Sendable {
    public var name: String
    public var type: UInt16
    public var qclass: UInt16

    public static let typeA: UInt16 = 1
    public static let typeCNAME: UInt16 = 5
    public static let typeAAAA: UInt16 = 28
    /// HTTPS / SVCB records advertise Encrypted ClientHello keys (§3.4).
    public static let typeHTTPS: UInt16 = 65
    public static let typeSVCB: UInt16 = 64
}

public struct DNSRecord: Equatable, Sendable {
    public var name: String
    public var type: UInt16
    public var ttl: UInt32
    public var data: [UInt8]

    /// "142.250.0.1" or an IPv6 string for A / AAAA records.
    public var address: String? {
        if type == DNSQuestion.typeA, data.count == 4 {
            return data.map(String.init).joined(separator: ".")
        }
        if type == DNSQuestion.typeAAAA, data.count == 16 {
            var addr = in6_addr()
            withUnsafeMutableBytes(of: &addr) { raw in
                for i in 0..<16 { raw[i] = data[i] }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        }
        return nil
    }
}

public struct DNSMessage: Equatable, Sendable {
    public var id: UInt16
    public var flags: UInt16
    public var questions: [DNSQuestion]
    public var answers: [DNSRecord]

    public var isResponse: Bool { flags & 0x8000 != 0 }
    public var responseCode: UInt16 { flags & 0x000F }

    /// Parses a message. Answers are read when present; authority and
    /// additional sections are ignored.
    public static func parse(_ bytes: [UInt8]) -> DNSMessage? {
        guard bytes.count >= 12 else { return nil }
        var r = Reader(bytes: bytes, position: 12)
        let id = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let qdCount = Int(bytes[4]) << 8 | Int(bytes[5])
        let anCount = Int(bytes[6]) << 8 | Int(bytes[7])
        guard qdCount <= 4, anCount <= 64 else { return nil }
        var questions: [DNSQuestion] = []
        for _ in 0..<qdCount {
            guard let name = r.name(), let type = r.u16(), let qclass = r.u16() else { return nil }
            questions.append(DNSQuestion(name: name, type: type, qclass: qclass))
        }
        var answers: [DNSRecord] = []
        for _ in 0..<anCount {
            guard let name = r.name(), let type = r.u16(), r.u16() != nil, let ttl = r.u32(),
                  let length = r.u16(), let data = r.take(length) else { break }
            answers.append(DNSRecord(name: name, type: type, ttl: ttl, data: Array(data)))
        }
        return DNSMessage(id: id, flags: flags, questions: questions, answers: answers)
    }

    // MARK: - Replies the proxy writes itself

    /// NXDOMAIN for the query in `query`: the name does not exist.
    public static func nxdomain(for query: [UInt8]) -> [UInt8]? {
        reply(to: query, rcode: 3, answers: [])
    }

    /// NOERROR with no records: used for HTTPS/SVCB queries while the guard is
    /// on, so no Encrypted ClientHello key ever reaches a browser.
    public static func empty(for query: [UInt8]) -> [UInt8]? {
        reply(to: query, rcode: 0, answers: [])
    }

    /// Answers the query with these addresses under the question's own name.
    /// Used for SafeSearch: `www.google.com` answers with
    /// `forcesafesearch.google.com`'s addresses.
    public static func addresses(for query: [UInt8], records: [DNSRecord], ttl: UInt32 = 300) -> [UInt8]? {
        guard let message = parse(query), let question = message.questions.first else { return nil }
        let matching = records.filter { $0.type == question.type && ($0.type == DNSQuestion.typeA || $0.type == DNSQuestion.typeAAAA) }
        return reply(to: query, rcode: 0, answers: matching.map { DNSRecord(name: question.name, type: $0.type, ttl: min($0.ttl, ttl), data: $0.data) })
    }

    /// The same query asking for a different name: how the proxy resolves a
    /// SafeSearch target with the upstream resolver.
    public static func query(_ query: [UInt8], renamedTo name: String) -> [UInt8]? {
        guard let message = parse(query), let question = message.questions.first else { return nil }
        var out = Array(query[0..<4])
        out += [0, 1, 0, 0, 0, 0, 0, 0] // one question, nothing else
        guard let encoded = encodeName(name) else { return nil }
        out += encoded
        out += u16(question.type) + u16(question.qclass)
        return out
    }

    private static func reply(to query: [UInt8], rcode: UInt16, answers: [DNSRecord]) -> [UInt8]? {
        guard let message = parse(query), let question = message.questions.first,
              let qname = encodeName(question.name) else { return nil }
        // QR=1, keep opcode and RD, RA=1, rcode.
        let flags: UInt16 = 0x8000 | (message.flags & 0x7900) | 0x0080 | rcode
        var out = u16(message.id) + u16(flags)
        out += u16(1) + u16(UInt16(answers.count)) + u16(0) + u16(0)
        out += qname + u16(question.type) + u16(question.qclass)
        for answer in answers {
            out += [0xC0, 0x0C] // pointer to the question name
            out += u16(answer.type) + u16(1) + u32(answer.ttl) + u16(UInt16(answer.data.count)) + answer.data
        }
        return out
    }

    static func encodeName(_ name: String) -> [UInt8]? {
        var out: [UInt8] = []
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
                let bytes = Array(label.utf8)
                guard !bytes.isEmpty, bytes.count <= 63 else { return nil }
                out.append(UInt8(bytes.count))
                out += bytes
            }
        }
        out.append(0)
        return out.count <= 255 ? out : nil
    }

    private static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    private static func u32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    private struct Reader {
        let bytes: [UInt8]
        var position: Int

        mutating func u16() -> UInt16? {
            guard position + 2 <= bytes.count else { return nil }
            defer { position += 2 }
            return UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1])
        }

        mutating func u32() -> UInt32? {
            guard position + 4 <= bytes.count else { return nil }
            defer { position += 4 }
            return bytes[position..<position + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func take(_ count: UInt16) -> ArraySlice<UInt8>? {
            let count = Int(count)
            guard position + count <= bytes.count else { return nil }
            defer { position += count }
            return bytes[position..<position + count]
        }

        /// A possibly compressed name. Pointer loops are cut off after 16 jumps.
        mutating func name() -> String? {
            var labels: [String] = []
            var cursor = position
            var jumped = false
            var jumps = 0
            var total = 0
            while true {
                guard cursor < bytes.count else { return nil }
                let length = Int(bytes[cursor])
                if length == 0 {
                    if !jumped { position = cursor + 1 }
                    break
                }
                if length & 0xC0 == 0xC0 {
                    guard cursor + 1 < bytes.count, jumps < 16 else { return nil }
                    let pointer = (length & 0x3F) << 8 | Int(bytes[cursor + 1])
                    if !jumped { position = cursor + 2 }
                    jumped = true
                    jumps += 1
                    cursor = pointer
                    continue
                }
                guard length <= 63, cursor + 1 + length <= bytes.count else { return nil }
                total += length + 1
                guard total <= 255 else { return nil }
                labels.append(String(decoding: bytes[(cursor + 1)...(cursor + length)], as: UTF8.self))
                cursor += 1 + length
            }
            return labels.joined(separator: ".").lowercased()
        }
    }
}

/// Where SafeSearch sends each search engine (PLAN.md M1.3). These are the
/// engines' own documented "force safe search" hosts.
public enum SafeSearch {
    public static let googleTarget = "forcesafesearch.google.com"
    public static let bingTarget = "strict.bing.com"
    public static let duckDuckGoTarget = "safe.duckduckgo.com"
    /// Moderate keeps ordinary videos and still removes explicit results (§10.8).
    public static let youtubeTarget = "restrictmoderate.youtube.com"

    static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtubei.googleapis.com",
        "youtube.googleapis.com", "www.youtube-nocookie.com",
    ]

    /// The host a DNS query for `host` should resolve as, or nil to leave it alone.
    public static func target(for host: String) -> String? {
        let h = ActiveRules.clean(host)
        if youtubeHosts.contains(h) { return youtubeTarget }
        if h == "bing.com" || h == "www.bing.com" { return bingTarget }
        if h == "duckduckgo.com" || h == "www.duckduckgo.com" || h == "start.duckduckgo.com" { return duckDuckGoTarget }
        if isGoogleSearchHost(h) { return googleTarget }
        return nil
    }

    /// google.com, www.google.com, google.co.uk, www.google.com.au … but not
    /// mail.google.com, docs.google.com or googleapis.com.
    static func isGoogleSearchHost(_ h: String) -> Bool {
        var labels = h.split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        guard labels.first == "google", labels.count >= 2, labels.count <= 3 else { return false }
        let suffix = labels.dropFirst()
        if suffix.count == 1 { return suffix.first!.count >= 2 && suffix.first!.count <= 3 }
        // google.co.uk, google.com.au
        return ["co", "com"].contains(suffix.first!) && suffix.last!.count == 2
    }
}
