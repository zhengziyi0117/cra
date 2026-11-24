import Foundation

/// What typed text means as an address: the command bar's rule for telling a URL from a search,
/// and the scheme it gets when it has none. Text without a scheme follows Chrome's omnibox
/// (AutocompleteInput::Parse), see `Parts.kind`.
public enum TypedURL {
    /// `typedHosts`: hosts whose address was entered in the bar before, with the scheme they were on.
    /// Text Chrome can't call (a word, "go/standup") opens on one of them, and is searched otherwise.
    public static func looksLikeURL(_ s: String, typedHosts: [String: String] = [:]) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.contains(" ") { return false }
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil { return true }
        if t.hasPrefix("localhost") || t.hasPrefix("about:") || t.hasPrefix("view-source:") || t.hasPrefix("data:") || t.hasPrefix("file:") { return true }
        guard let parts = Parts(t) else { return false }
        switch parts.kind {
        case .url: return true
        case .query: return false
        case .unknown: return typedHosts[parts.host.lowercased()] != nil
        }
    }

    /// The address for typed text. Without a scheme: https, as Chrome upgrades a typed address, but
    /// http for what Chrome never upgrades (an IP address, a host with no known TLD such as an
    /// intranet "go" or "nas.local", an address with a port), and a typed host's own scheme.
    public static func fromInput(_ s: String, typedHosts: [String: String] = [:]) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil { return t }
        // Before the bare-scheme check: "localhost:3000" is a host and port, not a "localhost:" URL.
        if t.hasPrefix("localhost") { return "http://" + t }
        if let parts = Parts(t) {
            if parts.kind == .unknown, let scheme = typedHosts[parts.host.lowercased()] { return scheme + "://" + t }
            return (parts.ipv4 != nil || parts.port != nil || !parts.hasKnownTLD ? "http://" : "https://") + t
        }
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) != nil { return t }
        return "https://" + t
    }

    /// The page a command bar "go to" row opens on Return. While the typed text is still what the
    /// row was made for, the row's own address. Text typed past it before the rows caught up (a comma
    /// after "example.com") opens only if it is an address itself; nil means search it (#512).
    public static func navigation(typed: String, rowURL: String?, rowIsForTyped: Bool) -> String? {
        if rowIsForTyped { return rowURL ?? fromInput(typed) }
        return looksLikeURL(typed) ? fromInput(typed) : nil
    }

    /// Arc's Edit Pinned URL dialog: the address a pinned tab or favorite gets from the typed text,
    /// or nil when it isn't one (a search, a script, a web address without a host).
    public static func pinnedDestination(_ s: String) -> String? {
        let input = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeURL(input) else { return nil }
        let url = fromInput(input)
        guard let parsed = URL(string: url) else { return nil }
        if ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host?.isEmpty != false { return nil }
        return url
    }

    /// Typed text without a scheme, cut as Chrome's SegmentURL does: host, then ":port", path, "?query", "#ref".
    struct Parts {
        enum Kind { case url, query, unknown }

        let host: String
        let port: Substring?
        let path: Substring
        let query: Substring?
        let ref: Substring?

        /// nil when it isn't host-first: "mailto:…" or "site:…" (not digits after the colon, so a
        /// scheme, as Chrome's HasPort tells), or a host no address has ("a,b", "@x").
        init?(_ t: String) {
            let stops: Set<Character> = [":", "/", "\\", "?", "#"]
            var rest = Substring(t)
            let host = rest.prefix { !stops.contains($0) }
            guard host.range(of: #"^[\w\-]+(\.[\w\-]+)*\.?$"#, options: .regularExpression) != nil else { return nil }
            rest = rest.dropFirst(host.count)
            var port: Substring?
            if rest.first == ":" {
                let p = rest.dropFirst().prefix { !"/\\?#".contains($0) }
                guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                port = p
                rest = rest.dropFirst(1 + p.count)
            }
            let path = rest.prefix { $0 != "?" && $0 != "#" }
            rest = rest.dropFirst(path.count)
            var query: Substring?
            if rest.first == "?" {
                let q = rest.dropFirst().prefix { $0 != "#" }
                query = q
                rest = rest.dropFirst(1 + q.count)
            }
            (self.host, self.port, self.path, self.query) = (String(host), port, path, query)
            ref = rest.first == "#" ? rest.dropFirst() : nil
        }

        private var labels: [Substring] {
            var l = host.split(separator: ".", omittingEmptySubsequences: false)
            if l.count > 1, l.last?.isEmpty == true { l.removeLast() }  // "example.com."
            return l
        }

        /// A host of digits and dots: its components and first octet, as Chrome's IPv4 canonicalizer
        /// reads "1.2" (1.0.0.2) or "1" (0.0.0.1). nil when it isn't one, or can't be one ("1.300.2.3").
        var ipv4: (components: Int, firstOctet: Int)? {
            let l = labels
            guard l.count <= 4, l.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
            let values = l.map { UInt64($0) ?? .max }
            if l.count == 1 { return values[0] <= 0xFFFF_FFFF ? (1, Int(values[0] >> 24)) : nil }
            guard values.dropLast().allSatisfy({ $0 <= 255 }), l.count < 4 || values[3] <= 255 else { return nil }
            return (l.count, Int(values[0]))
        }

        /// A host under a top-level domain (KnownTLDs; a non-ASCII one, which Chrome would read as
        /// its xn-- form, counts). A bare "com" has none.
        var hasKnownTLD: Bool {
            let l = labels
            guard l.count > 1, let tld = l.last else { return false }
            return !tld.allSatisfy(\.isASCII) || KnownTLDs.contains(String(tld))
        }

        /// Chrome's verdict, in its order (autocomplete_input.cc): an IP address with four parts; a
        /// trailing slash; more than one of port, path, query and ref; a known TLD or a port; a
        /// subdomain of .example, .test, .local or .internal. Two or three numbers ("3.14",
        /// "13.5/7.25") and a zero first octet ("1/2") are searches. Anything else is unknown.
        var kind: Kind {
            if let ip = ipv4 {
                // A zero first octet is a source address, never a destination; 0.0.0.0 reaches localhost.
                let zero = labels.allSatisfy { UInt64($0) == 0 }
                if ip.components == 4, ip.firstOctet != 0 || zero { return .url }
                if ip.firstOctet == 0 { return .query }
            }
            if let last = path.last, last == "/" || last == "\\" { return .url }
            if let ip = ipv4, ip.components > 1 { return .query }
            let others = [port, path.isEmpty ? nil : path, query, ref].filter { !($0?.isEmpty ?? true) }.count
            if others > 1 { return .url }
            if hasKnownTLD || port?.isEmpty == false { return .url }
            if labels.count > 1, let tld = labels.last, ["example", "test", "local", "internal"].contains(tld.lowercased()) { return .url }
            return .unknown
        }
    }
}
