import Foundation

/// Assembles a Markdown document from structural blocks.
///
/// The builder owns all escaping so that individual converters never have to
/// reason about Markdown syntax. Blocks are separated by exactly one blank line,
/// which keeps the output stable and diff friendly.
public struct MarkdownBuilder: Sendable {

    /// The horizontal alignment of a table column.
    public enum ColumnAlignment: Sendable, Equatable {
        case leading
        case center
        case trailing

        fileprivate var delimiter: String {
            switch self {
            case .leading: return ":---"
            case .center: return ":---:"
            case .trailing: return "---:"
            }
        }
    }

    private var blocks: [String] = []

    public init() {}

    /// Indicates whether any content has been appended.
    public var isEmpty: Bool { blocks.isEmpty }

    // MARK: - Blocks

    /// Appends an ATX heading clamped to levels one through six.
    public mutating func addHeading(_ text: String, level: Int) {
        let trimmed = text.trimmedForMarkdown
        guard !trimmed.isEmpty else { return }
        let clampedLevel = min(max(level, 1), 6)
        let hashes = String(repeating: "#", count: clampedLevel)
        blocks.append("\(hashes) \(Self.escape(trimmed, inline: true))")
    }

    /// Appends a body paragraph, collapsing internal line breaks into spaces.
    public mutating func addParagraph(_ text: String) {
        let collapsed = text
            .components(separatedBy: .newlines)
            .map { $0.trimmedForMarkdown }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return }
        blocks.append(Self.escape(collapsed, inline: false))
    }

    /// Appends a bulleted or numbered list.
    ///
    /// - Parameters:
    ///   - items: The list item contents, in order.
    ///   - ordered: Pass `true` to emit a numbered list.
    ///   - indentLevel: The nesting depth, where zero is the outermost level.
    public mutating func addList(_ items: [String], ordered: Bool = false, indentLevel: Int = 0) {
        let indent = String(repeating: "  ", count: max(indentLevel, 0))
        let rendered = items
            .map { $0.trimmedForMarkdown }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, item in
                let marker = ordered ? "\(index + 1)." : "-"
                return "\(indent)\(marker) \(Self.escape(item, inline: true))"
            }
        guard !rendered.isEmpty else { return }
        blocks.append(rendered.joined(separator: "\n"))
    }

    /// Appends a fenced code block, widening the fence if the body contains one.
    public mutating func addCodeBlock(_ code: String, language: String? = nil) {
        let backtickRun = code.longestRun(of: "`")
        let fence = String(repeating: "`", count: max(3, backtickRun + 1))
        let body = code.trimmingCharacters(in: .newlines)
        blocks.append("\(fence)\(language ?? "")\n\(body)\n\(fence)")
    }

    /// Appends a block quote, prefixing every line.
    public mutating func addBlockQuote(_ text: String) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmedForMarkdown }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        blocks.append(lines.map { "> \(Self.escape($0, inline: true))" }.joined(separator: "\n"))
    }

    /// Appends a GitHub flavoured table.
    ///
    /// Rows shorter than the header are padded and longer rows are truncated, so
    /// that the emitted table is always rectangular and therefore parseable.
    public mutating func addTable(
        headers: [String],
        rows: [[String]],
        alignments: [ColumnAlignment] = []
    ) {
        guard !headers.isEmpty else { return }

        let columnCount = headers.count
        let headerLine = Self.tableRow(headers, columnCount: columnCount)
        let delimiters = (0..<columnCount).map { index -> String in
            index < alignments.count ? alignments[index].delimiter : "---"
        }
        let delimiterLine = "| \(delimiters.joined(separator: " | ")) |"
        let bodyLines = rows.map { Self.tableRow($0, columnCount: columnCount) }

        blocks.append(([headerLine, delimiterLine] + bodyLines).joined(separator: "\n"))
    }

    /// Appends a thematic break.
    public mutating func addThematicBreak() {
        blocks.append("---")
    }

    /// Appends pre-rendered Markdown without escaping.
    ///
    /// - Important: The caller is responsible for the validity of `markdown`.
    public mutating func addRawBlock(_ markdown: String) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocks.append(trimmed)
    }

    // MARK: - Output

    /// Renders the accumulated blocks into a Markdown document.
    ///
    /// The result is newline terminated when it is not empty.
    public func build() -> String {
        guard !blocks.isEmpty else { return "" }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Escaping

    /// Escapes Markdown significant characters in `text`.
    ///
    /// - Parameters:
    ///   - text: The literal text to escape.
    ///   - inline: Pass `true` when the text is already inside a block whose
    ///     leading marker has been emitted, which suppresses block-level
    ///     prefix escaping.
    public static func escape(_ text: String, inline: Bool = false) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)

        for character in text {
            if Self.inlineEscapableCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        guard !inline else { return escaped }
        return Self.escapingLeadingBlockMarker(in: escaped)
    }

    private static let inlineEscapableCharacters: Set<Character> = [
        "\\", "`", "*", "_", "[", "]", "<", ">"
    ]

    /// Escapes a leading character that would otherwise start a new block.
    private static func escapingLeadingBlockMarker(in text: String) -> String {
        guard let first = text.first else { return text }

        if first == "#" || first == ">" || first == "-" || first == "+" {
            return "\\" + text
        }

        // An ordered list marker is only significant when followed by a period.
        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, text.dropFirst(digits.count).first == "." {
            return digits + "\\" + text.dropFirst(digits.count)
        }

        return text
    }

    private static func tableRow(_ cells: [String], columnCount: Int) -> String {
        var normalized = cells.prefix(columnCount).map { cell in
            escape(cell.trimmedForMarkdown, inline: true)
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
        while normalized.count < columnCount {
            normalized.append("")
        }
        return "| \(normalized.joined(separator: " | ")) |"
    }
}

// MARK: - Helpers

extension String {

    /// The receiver with leading and trailing whitespace removed.
    fileprivate var trimmedForMarkdown: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The length of the longest consecutive run of `character`.
    fileprivate func longestRun(of character: Character) -> Int {
        var longest = 0
        var current = 0
        for element in self {
            if element == character {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}
