import Foundation

/// A curated "platform" — one product a person reaches many ways (its app, its
/// mobile and desktop sites, its content/CDN hosts). The user assigns a platform
/// ONE class and Prosper clusters everything that belongs to it under that class.
///
/// Clustering is by **name**, not exact domain, because iOS attributes the real
/// time to many hosts a person never types: YouTube video streams from
/// `*.googlevideo.com`, Facebook content from `*.fbcdn.net`, Instagram from
/// `*.cdninstagram.com`. Matching the platform's keywords anywhere in an app's
/// name or a web domain catches all of them — and matches the app by its display
/// name, so we don't need Apple's picker to classify apps either.
struct Platform: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// SF Symbol drawn inside the platform's brand tile (see `BrandMark`), and
    /// on its own in the classification editor.
    let symbol: String
    /// The platform's own brand colour, 0xRRGGBB. Used for the tile we draw
    /// wherever iOS gives us no real app icon — websites, and every surface
    /// outside the report extension (see `UsageIcon`).
    let tintHex: UInt
    /// Concrete registrable domains — used for blocking/warnings, which must name
    /// exact hosts (keyword matching can't drive a content filter).
    let domains: [String]
    /// Lowercased substrings that mark a host or app name as this platform. Kept
    /// specific (never a bare letter) so clustering doesn't over-reach. Includes
    /// the CDN/asset hosts iOS actually books the time against.
    let keywords: [String]
    /// A sensible built-in class for platforms whose nature is unambiguous — the
    /// big social feeds are `.distracting`, work tools are `.productive`. Applied
    /// only as a last resort, so a user's own label always wins (UX-20). Genuinely
    /// ambiguous products (YouTube, WhatsApp, Netflix…) leave this `nil` so the
    /// user decides.
    var defaultClass: SharedClassification.ClassKind? = nil

    /// The host shown to represent the platform.
    var primaryDomain: String { domains[0] }

    /// Whether an already-lowercased app name or web host belongs to this
    /// platform.
    ///
    /// A keyword containing a dot is a host, and only matches on a whole DNS
    /// label — otherwise "t.co" would claim `reddi**t.co**m` and `microsof**t.co**m`,
    /// and their time would be filed under X. Everything else is a plain
    /// substring, which is what catches app display names and CDN hosts
    /// ("youtube" in "YouTube Music" and in "r1---sn-x.googlevideo.com").
    func matches(_ lowercasedText: String) -> Bool {
        keywords.contains { keyword in
            if keyword.contains(".") {
                return lowercasedText == keyword || lowercasedText.hasSuffix("." + keyword)
            }
            return lowercasedText.contains(keyword)
        }
    }
}

enum PlatformCatalog {
    /// Ordered roughly by how often they eat time. The custom-site field handles
    /// anything not here.
    static let all: [Platform] = [
        Platform(id: "facebook",  name: "Facebook",    symbol: "f.cursive",        tintHex: 0x1877F2, domains: ["facebook.com", "fb.com", "messenger.com"], keywords: ["facebook", "fbcdn", "fbsbx", "messenger"], defaultClass: .distracting),
        Platform(id: "instagram", name: "Instagram",   symbol: "camera.fill",      tintHex: 0xE1306C, domains: ["instagram.com"],                            keywords: ["instagram", "cdninstagram"], defaultClass: .distracting),
        Platform(id: "youtube",   name: "YouTube",     symbol: "play.fill",        tintHex: 0xFF0000, domains: ["youtube.com", "youtu.be"],                  keywords: ["youtube", "youtu.be", "ytimg", "googlevideo", "ggpht"]),
        Platform(id: "tiktok",    name: "TikTok",      symbol: "music.note",       tintHex: 0xFF0050, domains: ["tiktok.com"],                               keywords: ["tiktok", "musical.ly", "tiktokcdn", "tiktokv"], defaultClass: .distracting),
        Platform(id: "x",         name: "X (Twitter)", symbol: "xmark",            tintHex: 0x14171A, domains: ["x.com", "twitter.com", "t.co"],             keywords: ["twitter", "twimg", "t.co", "x.com"], defaultClass: .distracting),
        Platform(id: "reddit",    name: "Reddit",      symbol: "bubble.left.fill", tintHex: 0xFF4500, domains: ["reddit.com", "redd.it"],                    keywords: ["reddit", "redd.it", "redditmedia", "redditstatic"], defaultClass: .distracting),
        Platform(id: "snapchat",  name: "Snapchat",    symbol: "bolt.fill",        tintHex: 0xFFFC00, domains: ["snapchat.com"],                             keywords: ["snapchat", "sc-cdn", "snapkit"], defaultClass: .distracting),
        Platform(id: "whatsapp",  name: "WhatsApp",    symbol: "phone.fill",       tintHex: 0x25D366, domains: ["whatsapp.com"],                             keywords: ["whatsapp"]),
        Platform(id: "netflix",   name: "Netflix",     symbol: "film.fill",        tintHex: 0xE50914, domains: ["netflix.com"],                              keywords: ["netflix", "nflx"]),
        Platform(id: "twitch",    name: "Twitch",      symbol: "gamecontroller.fill", tintHex: 0x9146FF, domains: ["twitch.tv"],                             keywords: ["twitch", "ttvnw", "jtvnw"]),
        Platform(id: "pinterest", name: "Pinterest",   symbol: "pin.fill",         tintHex: 0xE60023, domains: ["pinterest.com"],                            keywords: ["pinterest", "pinimg"], defaultClass: .distracting),
        Platform(id: "linkedin",  name: "LinkedIn",    symbol: "briefcase.fill",   tintHex: 0x0A66C2, domains: ["linkedin.com"],                             keywords: ["linkedin", "licdn"]),
        // Work tools — pre-classified productive (a user can still relabel them).
        Platform(id: "zoom",      name: "Zoom",        symbol: "video.fill",       tintHex: 0x2D8CFF, domains: ["zoom.us"],                                  keywords: ["zoom.us", "zoomgov.com", "zoom"], defaultClass: .productive),
        Platform(id: "slack",     name: "Slack",       symbol: "message.fill",     tintHex: 0x4A154B, domains: ["slack.com"],                                keywords: ["slack.com", "slack-edge.com", "slack-imgs.com", "slack"], defaultClass: .productive),
        Platform(id: "teams",     name: "Microsoft Teams", symbol: "person.2.fill", tintHex: 0x6264A7, domains: ["teams.microsoft.com"],                    keywords: ["microsoft teams", "teams.microsoft.com", "teams.live.com", "msteams"], defaultClass: .productive),
        Platform(id: "gmail",     name: "Gmail",       symbol: "envelope.fill",    tintHex: 0xEA4335, domains: ["mail.google.com", "gmail.com"],             keywords: ["gmail", "googlemail.com", "mail.google.com"], defaultClass: .productive),
    ]

    /// Every domain owned by any catalog platform, lowercased — used to keep the
    /// custom-site list from repeating a host a platform already manages.
    static let allDomains: Set<String> = Set(all.flatMap { $0.domains.map { $0.lowercased() } })

    /// The platform an app name or web host belongs to (case-insensitive), or
    /// nil. Returns the first catalog platform whose keyword matches `text`.
    static func match(_ text: String?) -> Platform? {
        guard let text, !text.isEmpty else { return nil }
        let hay = text.lowercased()
        return all.first { $0.matches(hay) }
    }

    /// The platform with this id, e.g. from a rolled-up usage row's `platformID`.
    static func platform(id: String) -> Platform? {
        all.first { $0.id == id }
    }

    /// Browsers whose own app time already *contains* the per-site time iOS
    /// reports separately. Anything ranked as a product subtracts the attributed
    /// website time from these rows, so browsing Instagram in Safari is not
    /// counted once as "Instagram" and again as "Safari" in the same list.
    ///
    /// Matched as whole words of the app's display name, never substrings: a
    /// substring "edge" claimed "Ledger Live" and "Knowledge", and "opera"
    /// claimed "Operator" — scaling their time away as if it were browsing and
    /// keeping them out of the concentration insight (QA-9). Whole words still
    /// catch "Microsoft Edge", "Opera GX", "Firefox Focus" and "Arc Search".
    static let browserKeywords: Set<String> = ["safari", "chrome", "firefox", "edge", "brave", "opera", "duckduckgo", "arc"]

    static func isBrowser(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        return words.contains { browserKeywords.contains(String($0)) }
    }
}
