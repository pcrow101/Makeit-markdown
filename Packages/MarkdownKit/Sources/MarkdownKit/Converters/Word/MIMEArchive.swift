import Foundation

/// Reads a MIME web archive (MHTML), the format Word uses for "Single File
/// Web Page" documents and Confluence uses when exporting pages to Word.
///
/// The archive holds one HTML part and the pictures it shows, each labelled
/// with the location or content ID the HTML uses to refer to it.
struct MIMEArchive {

    /// The HTML of the page.
    let html: String

    /// The archive's other parts, keyed by `Content-Location` and by
    /// `cid:` content ID.
    let resources: [String: Data]

    /// Whether `data` starts like a MIME message.
    static func isMIME(_ data: Data) -> Bool {
        let head = (String(bytes: data.prefix(4096), encoding: .isoLatin1) ?? "").lowercased()
        return head.contains("mime-version:") && head.contains("content-type: multipart/")
    }

    /// Parses `data`, returning `nil` when it holds no HTML part.
    init?(data: Data) {
        // Latin-1 maps every byte to one character, so the message can be
        // split as text and each part turned back into its exact bytes.
        guard let message = String(data: data, encoding: .isoLatin1) else { return nil }
        let (headers, body) = Self.split(message)
        guard let boundary = Self.parameter("boundary", in: headers["content-type"] ?? "") else { return nil }

        var html: String?
        var resources: [String: Data] = [:]

        for part in body.components(separatedBy: "--" + boundary).dropFirst() {
            guard !part.hasPrefix("--") else { break }
            let (partHeaders, partBody) = Self.split(part)
            let content = Self.decode(partBody, encoding: partHeaders["content-transfer-encoding"])
            let type = partHeaders["content-type"] ?? ""

            if html == nil, type.lowercased().hasPrefix("text/html") {
                html = Self.text(content, charset: Self.parameter("charset", in: type))
                continue
            }
            if let location = partHeaders["content-location"] {
                resources[location] = content
            }
            if let identifier = partHeaders["content-id"] {
                let bare = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
                resources["cid:" + bare] = content
            }
        }

        guard let html else { return nil }
        self.html = html
        self.resources = resources
    }

    /// The data of the part a picture's `src` refers to.
    func resource(for source: String) -> Data? {
        if let exact = resources[source] { return exact }
        let name = Self.lastComponent(of: source)
        return resources.first { Self.lastComponent(of: $0.key) == name }?.value
    }

    private static func lastComponent(of path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        return decoded.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? decoded
    }

    // MARK: - Parsing

    /// Splits a message or part into its unfolded, lowercased headers and body.
    private static func split(_ text: String) -> ([String: String], String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.drop { $0 == "\n" }
        let parts = trimmed.split(separator: "\n\n", maxSplits: 1, omittingEmptySubsequences: false)
        let headerText = parts.first.map(String.init) ?? ""
        let body = parts.count > 1 ? String(parts[1]) : ""

        var headers: [String: String] = [:]
        var lastName: String?
        for line in headerText.split(separator: "\n") {
            if line.first == " " || line.first == "\t", let name = lastName {
                headers[name, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                lastName = name
            }
        }
        return (headers, body)
    }

    /// The value of a `name=value` parameter in a header.
    private static func parameter(_ name: String, in header: String) -> String? {
        for field in header.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == name else { continue }
            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
        }
        return nil
    }

    private static func decode(_ body: String, encoding: String?) -> Data {
        switch encoding?.lowercased() {
        case "base64"?:
            let compact = body.filter { !$0.isWhitespace }
            return Data(base64Encoded: compact, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable"?:
            return decodeQuotedPrintable(body)
        default:
            return body.data(using: .isoLatin1) ?? Data()
        }
    }

    static func decodeQuotedPrintable(_ body: String) -> Data {
        let bytes = Array((body.data(using: .isoLatin1) ?? Data()))
        var output = Data(capacity: bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "=") else {
                output.append(byte)
                index += 1
                continue
            }
            // A soft line break joins two encoded lines.
            if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\n") {
                index += 2
                continue
            }
            if index + 2 < bytes.count,
               let digits = String(bytes: bytes[(index + 1)...(index + 2)], encoding: .ascii),
               let value = UInt8(digits, radix: 16) {
                output.append(value)
                index += 3
                continue
            }
            output.append(byte)
            index += 1
        }
        return output
    }

    private static func text(_ data: Data, charset: String?) -> String {
        if let charset {
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if encoding != kCFStringEncodingInvalidId {
                let converted = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
                if let text = String(data: data, encoding: converted) { return text }
            }
        }
        return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .windowsCP1252) ?? ""
    }
}
