import Foundation

/// A block level element of a Markdown document.
///
/// `AttributedString` can only parse inline Markdown. Asking it for a whole
/// document either leaves the block syntax visible as literal text or discards
/// the structure entirely, and neither can show a table. Parsing into blocks
/// lets each one be drawn with the view that suits it.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case list(items: [Item], ordered: Bool)
    case table(headers: [String], rows: [[String]])
    case code(text: String, language: String?)
    case quote(text: String)
    case thematicBreak

    /// One entry of a bulleted or numbered list.
    struct Item: Equatable {
        var text: String
        var depth: Int
    }
}

/// Splits Markdown into the blocks that make it up.
///
/// The grammar recognised is the subset this app emits, which keeps the parser
/// small enough to be read and tested. Anything unrecognised falls through to a
/// paragraph, so no text is ever dropped.
enum MarkdownParser {

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = codeFenceLanguage(of: trimmed) {
                let (block, next) = parseCode(lines, from: index, language: fence)
                blocks.append(block)
                index = next
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isTableStart(lines, at: index) {
                let (block, next) = parseTable(lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            if listMarker(of: line) != nil {
                let (block, next) = parseList(lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            if trimmed.hasPrefix(">") {
                let (block, next) = parseQuote(lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            let (block, next) = parseParagraph(lines, from: index)
            blocks.append(block)
            index = next
        }

        return blocks
    }

    // MARK: - Headings and rules

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }

        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }

        return .heading(
            level: hashes.count,
            text: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } || trimmed.allSatisfy { $0 == "*" }
    }

    // MARK: - Code

    private static func codeFenceLanguage(of trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "" : language
    }

    private static func parseCode(
        _ lines: [String],
        from start: Int,
        language: String
    ) -> (MarkdownBlock, Int) {
        var body: [String] = []
        var index = start + 1

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            body.append(lines[index])
            index += 1
        }

        return (
            .code(text: body.joined(separator: "\n"), language: language.isEmpty ? nil : language),
            index
        )
    }

    // MARK: - Tables

    /// Whether a table begins at `index`.
    ///
    /// A table needs a header row and the delimiter row beneath it; a lone row
    /// of pipes is ordinary text.
    static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        guard lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return false }
        return isDelimiterRow(lines[index + 1])
    }

    private static func isDelimiterRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }

        let cells = splitRow(trimmed)
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            let body = cell.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return false }
            // A delimiter cell is dashes, optionally anchored with colons.
            return body.allSatisfy { $0 == "-" || $0 == ":" } && body.contains("-")
        }
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        let headers = splitRow(lines[start])
        var rows: [[String]] = []
        var index = start + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { break }

            var cells = splitRow(trimmed)
            // Keep every row rectangular so the grid lines up.
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            index += 1
        }

        return (.table(headers: headers, rows: rows), index)
    }

    /// Splits a table row into its cells.
    ///
    /// An escaped pipe is content rather than a cell boundary, so the escape is
    /// tracked while scanning. The backslash is left in place for the inline
    /// parser to resolve.
    static func splitRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var hasOpened = false

        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }

            if character == "|" {
                if hasOpened { cells.append(current) }
                current = ""
                hasOpened = true
                continue
            }

            current.append(character)
        }

        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Lists

    /// A list marker and the text that follows it.
    private struct Marker {
        var isOrdered: Bool
        var text: String
        var depth: Int
    }

    /// The marker of a list item, or `nil` when the line is not one.
    private static func listMarker(of line: String) -> Marker? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }

        if first == "-" || first == "*" || first == "+" {
            let rest = trimmed.dropFirst()
            guard rest.first == " " else { return nil }
            return Marker(
                isOrdered: false,
                text: rest.trimmingCharacters(in: .whitespaces),
                depth: indent / 2
            )
        }

        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let separator = afterDigits.first, separator == "." || separator == ")" else {
            return nil
        }
        let rest = afterDigits.dropFirst()
        guard rest.first == " " else { return nil }

        return Marker(
            isOrdered: true,
            text: rest.trimmingCharacters(in: .whitespaces),
            depth: indent / 2
        )
    }

    private static func parseList(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        var items: [MarkdownBlock.Item] = []
        var ordered = false
        var index = start

        while index < lines.count, let marker = listMarker(of: lines[index]) {
            if items.isEmpty { ordered = marker.isOrdered }
            // A change of kind starts a new list rather than continuing this one.
            guard marker.isOrdered == ordered else { break }

            items.append(MarkdownBlock.Item(text: marker.text, depth: marker.depth))
            index += 1
        }

        return (.list(items: items, ordered: ordered), index)
    }

    // MARK: - Quotes and paragraphs

    private static func parseQuote(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        var body: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            body.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            index += 1
        }

        return (.quote(text: body.joined(separator: " ")), index)
    }

    private static func parseParagraph(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        var body: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { break }
            if parseHeading(trimmed) != nil { break }
            if isThematicBreak(trimmed) { break }
            if codeFenceLanguage(of: trimmed) != nil { break }
            if listMarker(of: line) != nil { break }
            if isTableStart(lines, at: index) { break }
            if trimmed.hasPrefix(">") { break }

            body.append(trimmed)
            index += 1
        }

        return (.paragraph(text: body.joined(separator: " ")), index)
    }
}
