import Foundation

/// Turns whatever the user typed ("https://www.Reddit.com/r/all", "youtube.com")
/// into a bare, lowercase domain suitable for `WebDomain(domain:)`.
public enum BlockDomain {
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<cut])
        }
        if let at = s.lastIndex(of: "@") {
            s = String(s[s.index(after: at)...])
        }
        if let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        if s.hasPrefix("www.") {
            s.removeFirst(4)
        }

        // An internationalised domain has to reach WebDomain as punycode. The
        // check below used Character.isLetter, which is true for "ü" and "中",
        // so "bücher.de" sailed through and was handed to the filter as UTF-8 —
        // accepted without complaint and blocking nothing. A site the user
        // believes is blocked and is not is the worst failure this type has, so
        // the conversion happens here and anything that will not convert is
        // refused out loud instead.
        if !s.allSatisfy(\.isASCII) {
            guard let encoded = URL(string: "https://" + s)?.host?.lowercased() else { return nil }
            s = encoded
        }

        let allowed = s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "." }
        guard allowed, s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."), !s.contains("..") else {
            return nil
        }
        return s
    }
}
