import Foundation

/// The routes a browser can take around a hostname filter, closed while the
/// guard is on (PLAN.md §3.4). Each is closed so that every flow on the Mac
/// keeps a name the filter can read.
public enum BypassRules {
    /// Encrypted-DNS endpoints browsers use for their own "secure DNS" setting.
    /// Blocked so DNS keeps going through the proxy, where SafeSearch and the
    /// guard list apply.
    public static let encryptedDNSHosts: [String] = [
        "dns.google", "dns.google.com", "8888.google", "cloudflare-dns.com",
        "mozilla.cloudflare-dns.com", "chrome.cloudflare-dns.com", "1dot1dot1dot1.cloudflare-dns.com",
        "one.one.one.one", "security.cloudflare-dns.com", "family.cloudflare-dns.com",
        "dns.quad9.net", "dns9.quad9.net", "dns10.quad9.net", "dns11.quad9.net",
        "doh.opendns.com", "doh.familyshield.opendns.com", "dns.nextdns.io", "nextdns.io",
        "dns.adguard.com", "dns.adguard-dns.com", "unfiltered.adguard-dns.com", "doh.cleanbrowsing.org",
        "doh.dns.sb", "dns.alidns.com", "doh.pub", "dns.controld.com", "freedns.controld.com",
        "doh.mullvad.net", "dns.mullvad.net", "dns.brave.com", "dns0.eu", "zero.dns0.eu",
        "doh.libredns.gr", "dns.switch.ch", "odvr.nic.cz",
    ]

    /// iCloud Private Relay ingress hosts. Blocked so Safari connects directly
    /// and its flows carry their real names.
    public static let privateRelayHosts: [String] = ["mask.icloud.com", "mask-h2.icloud.com", "mask-api.icloud.com"]

    /// Public resolvers by address, for DNS-over-HTTPS that skips the name.
    public static let resolverAddresses: Set<String> = [
        "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1", "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15",
        "2001:4860:4860::8888", "2001:4860:4860::8844", "2606:4700:4700::1111", "2606:4700:4700::1001",
        "2620:fe::fe", "2620:fe::9",
    ]

    static let hostMatcher = DomainMatcher(encryptedDNSHosts + privateRelayHosts)

    public static func isBypassHost(_ host: String) -> Bool { hostMatcher.matchedDomain(host) != nil }

    /// What to do with a flow before it is named, while the guard is on.
    public enum PortVerdict: Equatable, Sendable { case allow, block }

    /// UDP 443 is QUIC (HTTP/3), whose ClientHello is encrypted: blocking it
    /// makes browsers fall back to TCP, where the server name is readable.
    /// Port 853 is DNS-over-TLS / DNS-over-QUIC. HTTPS straight to a public
    /// resolver's address is DNS-over-HTTPS without a name.
    public static func verdict(isUDP: Bool, remotePort: Int, remoteAddress: String?) -> PortVerdict {
        if isUDP && remotePort == 443 { return .block }
        if remotePort == 853 { return .block }
        if remotePort == 443, let address = remoteAddress, resolverAddresses.contains(address) { return .block }
        return .allow
    }
}
