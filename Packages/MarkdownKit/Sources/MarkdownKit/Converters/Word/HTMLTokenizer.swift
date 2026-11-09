import Foundation

/// A piece of an HTML document.
enum HTMLToken: Equatable {
    case text(String)
    case start(name: String, attributes: [String: String])
    case end(name: String)
}

/// A forgiving HTML tokenizer.
///
/// Word and Confluence write HTML that is not well formed XML, so
/// `XMLParser` cannot read it. The tokenizer only splits the markup into tags
/// and text: comments, declarations and conditional comments are dropped, and
/// the contents of `script`, `style`, `title` and Office `xml` islands are
/// skipped. Tag and attribute names are lowercased, and entities are decoded.
enum HTMLTokenizer {

    private static let rawTextElements: Set<String> = ["script", "style", "title", "xml", "template"]

    static func tokens(in html: String) -> [HTMLToken] {
        let scalars = Array(html.unicodeScalars)
        var tokens: [HTMLToken] = []
        var text = String.UnicodeScalarView()
        var index = 0

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(decodeEntities(String(text))))
            text = String.UnicodeScalarView()
        }

        while index < scalars.count {
            guard scalars[index] == "<", index + 1 < scalars.count, isMarkupStart(scalars[index + 1]) else {
                text.append(scalars[index])
                index += 1
                continue
            }
            flushText()

            if scalars[index + 1] == "!" || scalars[index + 1] == "?" {
                index = endOfDeclaration(in: scalars, from: index)
                continue
            }

            let (token, next) = tag(in: scalars, from: index)
            index = next
            guard let token else { continue }
            tokens.append(token)

            if case .start(let name, _) = token, rawTextElements.contains(name) {
                index = endOfRawText(named: name, in: scalars, from: index)
            }
        }
        flushText()
        return tokens
    }

    private static func isMarkupStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "/" || scalar == "!" || scalar == "?" || CharacterSet.letters.contains(scalar)
    }

    // MARK: - Markup

    /// The index just past a comment, doctype or conditional comment.
    private static func endOfDeclaration(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        if hasPrefix("<!--", in: scalars, at: start) {
            return endIndex(of: "-->", in: scalars, from: start + 4)
        }
        if hasPrefix("<![CDATA[", in: scalars, at: start) {
            return endIndex(of: "]]>", in: scalars, from: start + 9)
        }
        return endIndex(of: ">", in: scalars, from: start + 1)
    }

    /// Reads the tag starting at `start`, returning the index after it.
    private static func tag(in scalars: [Unicode.Scalar], from start: Int) -> (HTMLToken?, Int) {
        let close = endOfTag(in: scalars, from: start + 1)
        let bodyEnd = close > start + 1 && scalars[close - 1] == ">" ? close - 1 : close
        var body = String(String.UnicodeScalarView(scalars[(start + 1)..<max(bodyEnd, start + 1)]))

        let isEnd = body.hasPrefix("/")
        if isEnd { body.removeFirst() }
        if body.hasSuffix("/") { body.removeLast() }

        let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()
        guard !name.isEmpty else { return (nil, close) }
        if isEnd { return (.end(name: name), close) }

        let attributes = parseAttributes(String(body.dropFirst(name.count)))
        return (.start(name: name, attributes: attributes), close)
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var rest = Substring(source)

        while true {
            rest = rest.drop { $0.isWhitespace || $0 == "/" }
            let name = rest.prefix { !$0.isWhitespace && $0 != "=" && $0 != "/" }
            guard !name.isEmpty else { break }
            rest = rest.dropFirst(name.count).drop(while: \.isWhitespace)

            var value = ""
            if rest.first == "=" {
                rest = rest.dropFirst().drop(while: \.isWhitespace)
                if let quote = rest.first, quote == "\"" || quote == "'" {
                    let body = rest.dropFirst().prefix { $0 != quote }
                    value = String(body)
                    rest = rest.dropFirst(body.count + 2)
                } else {
                    let body = rest.prefix { !$0.isWhitespace }
                    value = String(body)
                    rest = rest.dropFirst(body.count)
                }
            }
            attributes[name.lowercased()] = decodeEntities(value)
        }
        return attributes
    }

    /// The index just past the closing tag of a raw text element.
    private static func endOfRawText(
        named name: String,
        in scalars: [Unicode.Scalar],
        from start: Int
    ) -> Int {
        let closing = Array("</\(name)".unicodeScalars)
        var index = start
        while index + closing.count <= scalars.count {
            if scalars[index] == "<", isClosingTag(closing, in: scalars, at: index) {
                return endIndex(of: ">", in: scalars, from: index + closing.count)
            }
            index += 1
        }
        return scalars.count
    }

    private static func isClosingTag(
        _ closing: [Unicode.Scalar],
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        for offset in closing.indices {
            let lhs = closing[offset].properties.lowercaseMapping
            let rhs = scalars[index + offset].properties.lowercaseMapping
            if lhs != rhs { return false }
        }
        return true
    }

    private static func hasPrefix(_ prefix: String, in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        matches(Array(prefix.unicodeScalars), in: scalars, at: index)
    }

    private static func matches(
        _ pattern: [Unicode.Scalar],
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        guard index >= 0, index + pattern.count <= scalars.count else { return false }
        for offset in pattern.indices where scalars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    /// The index just past the next `terminator`, or the end of the input.
    private static func endIndex(
        of terminator: String,
        in scalars: [Unicode.Scalar],
        from start: Int
    ) -> Int {
        let pattern = Array(terminator.unicodeScalars)
        var index = start
        while index + pattern.count <= scalars.count {
            if matches(pattern, in: scalars, at: index) {
                return index + pattern.count
            }
            index += 1
        }
        return scalars.count
    }

    /// The index just past the `>` that ends a tag, ignoring any `>` inside a
    /// quoted attribute value.
    private static func endOfTag(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        var quote: Unicode.Scalar?
        var previous: Unicode.Scalar = " "
        var index = start
        while index < scalars.count {
            let scalar = scalars[index]
            if let open = quote {
                if scalar == open { quote = nil }
            } else if scalar == ">" {
                return index + 1
            } else if (scalar == "\"" || scalar == "'") && previous == "=" {
                quote = scalar
            }
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) { previous = scalar }
            index += 1
        }
        return scalars.count
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "hellip": "\u{2026}", "bull": "\u{2022}",
        "middot": "\u{00B7}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "deg": "\u{00B0}", "times": "\u{00D7}", "divide": "\u{00F7}", "euro": "\u{20AC}",
        "pound": "\u{00A3}", "rarr": "\u{2192}", "larr": "\u{2190}", "laquo": "\u{00AB}",
        "raquo": "\u{00BB}", "shy": ""
    ]

    /// `text` with character references replaced by the characters they name.
    /// Unknown references are left as written.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var output = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            output += rest[..<ampersand]
            rest = rest[ampersand...]

            let candidate = rest.dropFirst().prefix(12)
            if let semicolon = candidate.firstIndex(of: ";"),
               let decoded = decode(String(candidate[..<semicolon])) {
                output += decoded
                rest = rest[rest.index(after: semicolon)...]
            } else {
                output += "&"
                rest = rest.dropFirst()
            }
        }
        return output + rest
    }

    private static func decode(_ reference: String) -> String? {
        if reference.hasPrefix("#") {
            let digits = reference.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[reference]
    }
}
