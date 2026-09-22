import Testing
@testable import Prosper

/// `BlockDomain.normalize` decides what actually reaches the web content
/// filter. Every wrong answer here is silent: the domain is accepted, the user
/// believes the site is blocked, and it simply is not. That is why this pure
/// function is the first thing worth testing (REL-15).
struct BlockDomainTests {

    // MARK: - Accepted

    @Test("A bare domain passes through unchanged")
    func bareDomain() {
        #expect(BlockDomain.normalize("reddit.com") == "reddit.com")
    }

    @Test("Case and surrounding whitespace are normalised")
    func caseAndWhitespace() {
        #expect(BlockDomain.normalize("  Reddit.COM  ") == "reddit.com")
        #expect(BlockDomain.normalize("\nYouTube.com\t") == "youtube.com")
    }

    @Test("Schemes are stripped", arguments: [
        "https://reddit.com",
        "http://reddit.com",
        "HTTPS://Reddit.com",
        "ftp://reddit.com",
    ])
    func schemes(_ input: String) {
        #expect(BlockDomain.normalize(input) == "reddit.com")
    }

    @Test("Paths, queries and fragments are stripped", arguments: [
        "reddit.com/r/all",
        "reddit.com/",
        "reddit.com?utm_source=x",
        "reddit.com#top",
        "https://www.reddit.com/r/all?sort=new#comments",
    ])
    func pathsAndQueries(_ input: String) {
        #expect(BlockDomain.normalize(input) == "reddit.com")
    }

    @Test("A leading www. is dropped so both spellings block the same site")
    func wwwPrefix() {
        #expect(BlockDomain.normalize("www.reddit.com") == "reddit.com")
        #expect(BlockDomain.normalize("https://www.reddit.com") == "reddit.com")
    }

    @Test("A www. that is part of the name is not eaten")
    func wwwLookalike() {
        #expect(BlockDomain.normalize("wwwreddit.com") == "wwwreddit.com")
    }

    @Test("Ports are stripped")
    func ports() {
        #expect(BlockDomain.normalize("reddit.com:8080") == "reddit.com")
        #expect(BlockDomain.normalize("https://reddit.com:443/r/all") == "reddit.com")
    }

    @Test("Userinfo is stripped, including a password containing @")
    func userinfo() {
        #expect(BlockDomain.normalize("user@reddit.com") == "reddit.com")
        #expect(BlockDomain.normalize("https://user:pass@reddit.com") == "reddit.com")
        #expect(BlockDomain.normalize("a@b@reddit.com") == "reddit.com")
    }

    @Test("Subdomains are preserved — old.reddit.com is not reddit.com")
    func subdomains() {
        #expect(BlockDomain.normalize("old.reddit.com") == "old.reddit.com")
        #expect(BlockDomain.normalize("news.ycombinator.com") == "news.ycombinator.com")
    }

    @Test("Hyphens and digits are legal in a hostname")
    func hyphensAndDigits() {
        #expect(BlockDomain.normalize("my-site7.co.uk") == "my-site7.co.uk")
    }

    // MARK: - Punycode
    //
    // The filter needs ASCII. A Unicode host that is accepted as-is is the
    // silent failure this whole type exists to prevent.

    @Test("An internationalised domain is converted to punycode")
    func punycodeConversion() {
        #expect(BlockDomain.normalize("bücher.de") == "xn--bcher-kva.de")
        #expect(BlockDomain.normalize("https://www.münchen.example") == "xn--mnchen-3ya.example")
    }

    @Test("A domain that is already punycode is left alone")
    func punycodePassthrough() {
        #expect(BlockDomain.normalize("xn--bcher-kva.de") == "xn--bcher-kva.de")
        #expect(BlockDomain.normalize("XN--BCHER-KVA.de") == "xn--bcher-kva.de")
    }

    @Test("Whatever comes back from conversion is ASCII")
    func conversionAlwaysASCII() throws {
        let result = try #require(BlockDomain.normalize("中国.cn"))
        #expect(result.allSatisfy { $0.isASCII })
    }

    // MARK: - Rejected
    //
    // Refusing loudly is the right answer: the UI shows an error, and the user
    // does not walk away believing something is blocked when it is not.

    @Test("Input with no dot is not a domain", arguments: ["reddit", "localhost", "a"])
    func noDot(_ input: String) {
        #expect(BlockDomain.normalize(input) == nil)
    }

    @Test("Empty and whitespace-only input is rejected", arguments: ["", "   ", "\n"])
    func empty(_ input: String) {
        #expect(BlockDomain.normalize(input) == nil)
    }

    @Test("Malformed dots are rejected", arguments: [".reddit.com", "reddit.com.", "reddit..com", "."])
    func malformedDots(_ input: String) {
        #expect(BlockDomain.normalize(input) == nil)
    }

    @Test("Characters that cannot appear in a hostname are rejected",
          arguments: ["red dit.com", "reddit_com.com", "red*dit.com", "red,dit.com"])
    func illegalCharacters(_ input: String) {
        #expect(BlockDomain.normalize(input) == nil)
    }

    @Test("A scheme with nothing after it is rejected")
    func schemeOnly() {
        #expect(BlockDomain.normalize("https://") == nil)
    }
}
