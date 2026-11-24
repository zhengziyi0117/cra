import CraCore
import Testing

struct TypedURLTests {
    @Test(arguments: [
        ("example.org/new?q=1", "https://example.org/new?q=1" as String?),
        ("  https://Example.com/a#b  ", "https://Example.com/a#b"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.1/admin", "http://192.168.1.1/admin"),
        ("file:///tmp/a.html", "file:///tmp/a.html"),
        ("about:blank", "about:blank"),
        ("", nil),
        ("hello world", nil),
        ("notes", nil),
        ("javascript:alert(1)", nil),
        ("https://", nil),
        ("http:///path", nil),
    ])
    func pinnedDestination(input: String, url: String?) {
        #expect(TypedURL.pinnedDestination(input) == url)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/512"))
    func textTypedPastAGoToRowIsSearchedUnlessItIsAnAddress() {
        // Still the row's text: the row's address.
        #expect(TypedURL.navigation(typed: "example.com", rowURL: "https://example.com/", rowIsForTyped: true) == "https://example.com/")
        // A comma typed before the rows caught up: not an address, so it is searched.
        #expect(TypedURL.navigation(typed: "example.com,", rowURL: "https://example.com/", rowIsForTyped: false) == nil)
        // More of an address typed past the row: that address.
        #expect(TypedURL.navigation(typed: "example.com/shop", rowURL: "https://example.com/", rowIsForTyped: false) == "https://example.com/shop")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/545"), arguments: [
        ("chapter-2.16", false),
        ("3.14", false),
        ("v2.5", false),
        ("example.com", true),
        ("sub.example.co.uk/path", true),
        ("example.com:8080/a", true),
        ("192.168.1.1", true),
        ("localhost:3000", true),
    ])
    func aTopLevelDomainHasALetter(input: String, isAddress: Bool) {
        #expect(TypedURL.looksLikeURL(input) == isAddress)
    }

    /// Text without a scheme as Chrome's omnibox takes it (AutocompleteInput::Parse), and the scheme
    /// it opens on: http for what Chrome never upgrades to https (an IP address, a host with no known
    /// TLD, an address with a port). nil: searched.
    @Test(arguments: [
        // A trailing slash makes an address: an intranet short link.
        ("git/", "http://git/" as String?),
        ("go/standup/", "http://go/standup/"),
        // More than one of port, path, query and ref.
        ("wiki/Team-Page?tab=1", "http://wiki/Team-Page?tab=1"),
        ("go/standup#notes", "http://go/standup#notes"),
        // A port, a known TLD, or a subdomain of a special-use one.
        ("devbox:8080", "http://devbox:8080"),
        ("example.com:8080/a", "http://example.com:8080/a"),
        ("example.com", "https://example.com"),
        ("nas.local", "http://nas.local"),
        ("build.internal/x", "http://build.internal/x"),
        // IP addresses: four parts, or a trailing slash; two or three numbers or a zero first octet search.
        ("10.0.0.1", "http://10.0.0.1"),
        ("1.2/", "http://1.2/"),
        ("13.5/7.25", nil),
        ("0.1.2.3", nil),
        ("1/2", nil),
        // Unknown (one word, a word and a path, an unknown TLD): searched unless typed before.
        ("go/standup", nil),
        ("notes", nil),
        ("java.awt", nil),
        ("browser.tabs.closeButtons", nil),
        // A scheme, not a port.
        ("site:example.com", nil),
    ])
    func textWithoutASchemeIsReadAsChromeReadsIt(input: String, url: String?) {
        #expect((TypedURL.looksLikeURL(input) ? TypedURL.fromInput(input) : nil) == url)
    }

    /// Chrome's known intranet host (HistoryURLProvider::AsKnownIntranetURL): text it can't call opens
    /// when its host's address was entered in the bar before, on that scheme.
    @Test func anUnknownHostTypedBeforeOpens() {
        let typed = ["go": "http", "notes": "https"]
        #expect(TypedURL.looksLikeURL("go/standup", typedHosts: typed))
        #expect(TypedURL.fromInput("go/standup", typedHosts: typed) == "http://go/standup")
        #expect(TypedURL.fromInput("notes", typedHosts: typed) == "https://notes")
        #expect(!TypedURL.looksLikeURL("wiki/standup", typedHosts: typed))
        // Only what Chrome can't call: "1/2" is a search whatever was typed.
        #expect(!TypedURL.looksLikeURL("1/2", typedHosts: ["1": "http"]))
    }

    @Test func searchesAreNotAddresses() {
        #expect(!TypedURL.looksLikeURL("cra browser"))
        #expect(TypedURL.looksLikeURL("view-source:https://example.com"))
        #expect(TypedURL.fromInput("example.com") == "https://example.com")
        #expect(TypedURL.fromInput("localhost:3000/a") == "http://localhost:3000/a")
        #expect(TypedURL.fromInput("http://localhost:3000") == "http://localhost:3000")
        #expect(TypedURL.fromInput("mailto:a@example.com") == "mailto:a@example.com")
    }
}
