import Foundation
import Testing
@testable import ProsperCore

/// Builds a realistic ClientHello: session id, ciphers, a few extensions
/// before and after the server name, as Chrome sends.
func clientHello(serverName: String?, padTo: Int = 0) -> [UInt8] {
    func u16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    var extensions: [UInt8] = []
    extensions += u16(0x0a0a) + u16(0) // GREASE
    extensions += u16(0x0017) + u16(0) // extended master secret
    if let serverName {
        let name = Array(serverName.utf8)
        let entry: [UInt8] = [0] + u16(name.count) + name
        let list = u16(entry.count) + entry
        extensions += u16(0x0000) + u16(list.count) + list
    }
    extensions += u16(0x002b) + u16(3) + [2, 0x03, 0x04] // supported versions
    if padTo > 0 { extensions += u16(0x0015) + u16(padTo) + Array(repeating: 0, count: padTo) }
    var body: [UInt8] = [0x03, 0x03] + Array(repeating: 7, count: 32)
    body += [32] + Array(repeating: 1, count: 32) // session id
    body += u16(6) + [0x13, 0x01, 0x13, 0x02, 0x13, 0x03]
    body += [1, 0]
    body += u16(extensions.count) + extensions
    let handshake: [UInt8] = [1, UInt8(body.count >> 16), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)] + body
    return [0x16, 0x03, 0x01] + u16(handshake.count) + handshake
}

struct SNIParserTests {
    @Test("Reads the server name from a ClientHello")
    func readsName() {
        #expect(SNIParser.parse(clientHello(serverName: "www.YouTube.com")) == .hostname("www.youtube.com"))
    }

    @Test("A ClientHello split across segments asks for more bytes, then succeeds")
    func fragmented() {
        let hello = clientHello(serverName: "rr3---sn-x.googlevideo.com", padTo: 1500)
        #expect(SNIParser.parse(Array(hello.prefix(3))) == .needMoreData)
        #expect(SNIParser.parse(Array(hello.prefix(60))) == .needMoreData)
        #expect(SNIParser.parse(hello) == .hostname("rr3---sn-x.googlevideo.com"))
    }

    @Test("No server name, and non-TLS bytes, are told apart")
    func noNameAndNotTLS() {
        #expect(SNIParser.parse(clientHello(serverName: nil)) == .noServerName)
        #expect(SNIParser.parse(Array("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) == .notTLS)
        #expect(SNIParser.parse([0x16, 0x03, 0x01, 0x00, 0x05, 0x02, 0, 0, 0, 0]) == .notTLS)
    }

    @Test("Garbage never crashes the parser")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        let hello = clientHello(serverName: "example.com")
        for _ in 0..<2000 {
            var bytes = hello
            for _ in 0..<4 {
                let i = Int.random(in: 0..<bytes.count, using: &generator)
                bytes[i] = UInt8.random(in: 0...255, using: &generator)
            }
            _ = SNIParser.parse(Array(bytes.prefix(Int.random(in: 0...bytes.count, using: &generator))))
        }
    }
}

func dnsQuery(_ name: String, type: UInt16 = 1, id: UInt16 = 0xBEEF) -> [UInt8] {
    var out: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
    out += DNSMessage.encodeName(name)!
    out += [UInt8(type >> 8), UInt8(type & 0xFF), 0, 1]
    return out
}

struct DNSMessageTests {
    @Test("Parses a query's question")
    func parseQuery() {
        let msg = DNSMessage.parse(dnsQuery("WWW.Google.com"))
        #expect(msg?.id == 0xBEEF)
        #expect(msg?.questions == [DNSQuestion(name: "www.google.com", type: 1, qclass: 1)])
        #expect(msg?.isResponse == false)
    }

    @Test("NXDOMAIN reply keeps the id and question")
    func nxdomain() {
        let reply = DNSMessage.nxdomain(for: dnsQuery("pornhub.com"))!
        let msg = DNSMessage.parse(reply)!
        #expect(msg.id == 0xBEEF)
        #expect(msg.isResponse)
        #expect(msg.responseCode == 3)
        #expect(msg.questions.first?.name == "pornhub.com")
        #expect(msg.answers.isEmpty)
    }

    @Test("SafeSearch: answers the original name with the target's addresses")
    func safeSearchAnswer() {
        let query = dnsQuery("www.google.com")
        let upstream = DNSRecord(name: "forcesafesearch.google.com", type: 1, ttl: 3600, data: [216, 239, 38, 120])
        let reply = DNSMessage.addresses(for: query, records: [upstream])!
        let msg = DNSMessage.parse(reply)!
        #expect(msg.answers.count == 1)
        #expect(msg.answers[0].name == "www.google.com")
        #expect(msg.answers[0].address == "216.239.38.120")
        #expect(msg.answers[0].ttl == 300)

        let renamed = DNSMessage.query(query, renamedTo: "forcesafesearch.google.com")!
        #expect(DNSMessage.parse(renamed)?.questions.first?.name == "forcesafesearch.google.com")
        #expect(DNSMessage.parse(renamed)?.id == 0xBEEF)
    }

    @Test("Compressed answer names and AAAA addresses parse")
    func compressed() {
        var reply = dnsQuery("a.com", type: 28)
        reply[2] = 0x81; reply[3] = 0x80; reply[7] = 1 // response, one answer
        reply += [0xC0, 0x0C, 0, 28, 0, 1, 0, 0, 0, 60, 0, 16] + [0x26, 0x06, 0x47, 0, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0x11]
        let msg = DNSMessage.parse(reply)!
        #expect(msg.answers.first?.name == "a.com")
        #expect(msg.answers.first?.address == "2606:4700:4700::1111")
    }

    @Test("A pointer loop does not hang the parser")
    func loop() {
        var bad: [UInt8] = [0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        bad += [0xC0, 0x0C, 0, 1, 0, 1]
        #expect(DNSMessage.parse(bad) == nil)
    }

    @Test("SafeSearch targets only the search hosts")
    func targets() {
        #expect(SafeSearch.target(for: "www.google.com") == SafeSearch.googleTarget)
        #expect(SafeSearch.target(for: "google.co.uk") == SafeSearch.googleTarget)
        #expect(SafeSearch.target(for: "www.google.com.au") == SafeSearch.googleTarget)
        #expect(SafeSearch.target(for: "mail.google.com") == nil)
        #expect(SafeSearch.target(for: "googleapis.com") == nil)
        #expect(SafeSearch.target(for: "www.bing.com") == SafeSearch.bingTarget)
        #expect(SafeSearch.target(for: "duckduckgo.com") == SafeSearch.duckDuckGoTarget)
        #expect(SafeSearch.target(for: "m.youtube.com") == SafeSearch.youtubeTarget)
        #expect(SafeSearch.target(for: "forcesafesearch.google.com") == nil)
    }
}

struct UsageTests {
    @Test("Recording splits across hours and counts distracting time")
    func record() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var day = UsageDay(day: "2026-11-08")
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9, minute: 50))!
        let end = start.addingTimeInterval(20 * 60)
        day.record(bundleID: "com.google.Chrome", app: AppUsage(name: "Google Chrome", isBrowser: true), site: "youtube.com", from: start, to: end, timeClass: .distracting, calendar: cal)
        #expect(day.hourly[9] == 600)
        #expect(day.hourly[10] == 600)
        #expect(day.distractingSeconds == 1200)
        #expect(day.sites["youtube.com"]?.seconds == 1200)
    }

    @Test("Browser time is not counted twice next to its sites")
    func noDoubleCount() {
        var day = UsageDay(day: "d")
        day.apps["com.apple.Safari"] = AppUsage(name: "Safari", seconds: 3600, opens: 3, isBrowser: true)
        day.apps["com.apple.dt.Xcode"] = AppUsage(name: "Xcode", seconds: 1800, opens: 1, category: "public.app-category.developer-tools")
        day.sites["youtube.com"] = SiteUsage(seconds: 2400, visits: 2)
        day.sites["github.com"] = SiteUsage(seconds: 600, visits: 1)
        let s = UsageSummary.build(days: [day], classifier: MacClassifier())
        #expect(s.totalSeconds == 5400)
        #expect(s.rows.reduce(0) { $0 + $1.seconds } == 5400)
        #expect(s.rows.first { $0.id == "platform:youtube" }?.seconds == 2400)
        #expect(s.rows.first { $0.id == "app:com.apple.Safari" }?.seconds == 600)
        #expect(s.distractingSeconds == 2400)
        #expect(s.productiveSeconds == 1800)
    }

    @Test("A user's label beats every default")
    func overrides() {
        let c = MacClassifier(settings: MacSettings(classOverrides: ["platform:youtube": .productive, "app:com.x": .rest]))
        #expect(c.timeClass(site: "youtube.com") == .productive)
        #expect(c.timeClass(bundleID: "com.x", name: "X", category: "public.app-category.games") == .rest)
        #expect(MacClassifier().timeClass(bundleID: "com.y", name: "Y", category: "public.app-category.games") == .distracting)
    }

    @Test("Registrable domain and duration text")
    func helpers() {
        #expect(RegistrableDomain.of("www.news.bbc.co.uk") == "bbc.co.uk")
        #expect(RegistrableDomain.of("m.youtube.com") == "youtube.com")
        #expect(RegistrableDomain.of("myapp-12ab.a.run.app") == "a.run.app")
        #expect(RegistrableDomain.of("mostafa.github.io") == "mostafa.github.io")
        #expect(DurationText.short(3900) == "1h 05m")
        #expect(DurationText.countdown(3849) == "1:04:09")
    }

    @Test("Rules survive a JSON round trip")
    func codable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (rules, _) = try RulesBook.startingSession(RulesBook.enablingGuard(.empty, now: now), minutes: 5, domains: ["a.com"], bundleIDs: [], platformIDs: [], now: now)
        let data = try MacStore.encoder.encode(rules)
        #expect(try MacStore.decoder.decode(MacRules.self, from: data) == rules)
    }
}
