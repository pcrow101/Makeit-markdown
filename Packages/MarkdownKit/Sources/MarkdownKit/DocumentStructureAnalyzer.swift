import Foundation

/// A single visual line of text extracted from a source document.
///
/// Lines carry the typographic measurements needed by the structure analyser.
/// Keeping them format agnostic means the heuristics can be exercised in tests
/// without constructing a real document.
public struct TextLine: Sendable, Equatable {

    /// The text content of the line, excluding trailing whitespace.
    public var text: String

    /// The dominant font point size on the line.
    public var fontSize: Double

    /// Whether the dominant font on the line is a bold face.
    public var isBold: Bool

    /// The horizontal offset of the line from the left edge of the page.
    public var indent: Double

    public init(text: String, fontSize: Double = 12, isBold: Bool = false, indent: Double = 0) {
        self.text = text
        self.fontSize = fontSize
        self.isBold = isBold
        self.indent = indent
    }
}

/// A structural element recovered from a sequence of ``TextLine`` values.
public enum DocumentBlock: Sendable, Equatable {
    case heading(text: String, level: Int)
    case paragraph(text: String)
    case listItem(text: String, ordered: Bool, indentLevel: Int)

    /// A tabular region recovered from the geometry of a page.
    ///
    /// The first row is treated as the header, because Markdown tables require
    /// one. `rows` is always rectangular.
    case table(rows: [[String]])
}

/// Recovers document structure from positioned text lines.
///
/// The analyser is deliberately conservative: anything it cannot classify with
/// reasonable confidence becomes a paragraph, because a plain paragraph is
/// always a safe representation for downstream language models.
public struct DocumentStructureAnalyzer: Sendable {

    private let options: ConversionOptions

    public init(options: ConversionOptions) {
        self.options = options
    }

    /// Groups `lines` into structural blocks.
    public func analyze(lines: [TextLine]) -> [DocumentBlock] {
        let meaningful = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !meaningful.isEmpty else { return [] }

        let bodyFontSize = Self.modalFontSize(of: meaningful)
        let minimumIndent = meaningful.map(\.indent).min() ?? 0

        var blocks: [DocumentBlock] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphBuffer.joined(separator: " ")))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for line in meaningful {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if options.detectLists, let item = ListMarker.parse(trimmed) {
                flushParagraph()
                let indentLevel = Self.indentLevel(
                    for: line,
                    relativeTo: minimumIndent,
                    bodyFontSize: bodyFontSize
                )
                blocks.append(
                    .listItem(text: item.content, ordered: item.isOrdered, indentLevel: indentLevel)
                )
                continue
            }

            if options.detectHeadings,
               let level = headingLevel(for: line, trimmed: trimmed, bodyFontSize: bodyFontSize) {
                flushParagraph()
                blocks.append(.heading(text: trimmed, level: level))
                continue
            }

            paragraphBuffer.append(trimmed)

            // A line that ends a sentence terminates the paragraph, which keeps
            // paragraphs from running together across unrelated content.
            if Self.terminatesParagraph(trimmed) {
                flushParagraph()
            }
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Heading detection

    /// Returns the heading level for `line`, or `nil` if it is body text.
    private func headingLevel(for line: TextLine, trimmed: String, bodyFontSize: Double) -> Int? {
        // Headings are short. A long line is prose regardless of its styling.
        guard trimmed.count <= Self.maximumHeadingLength else { return nil }

        // Prose that ends in sentence punctuation is not a heading.
        guard !trimmed.hasSuffix(".") && !trimmed.hasSuffix(",") && !trimmed.hasSuffix(";") else {
            return nil
        }

        let ratio = bodyFontSize > 0 ? line.fontSize / bodyFontSize : 1

        switch ratio {
        case Self.titleRatio...:
            return 1
        case Self.majorHeadingRatio..<Self.titleRatio:
            return 2
        case Self.minorHeadingRatio..<Self.majorHeadingRatio:
            return 3
        default:
            // Same size as body text, but bold and standing alone: a run-in heading.
            return line.isBold ? 4 : nil
        }
    }

    /// The font size shared by the greatest number of lines, treated as body text.
    private static func modalFontSize(of lines: [TextLine]) -> Double {
        var histogram: [Double: Int] = [:]
        for line in lines {
            // Bucket to a tenth of a point to tolerate sub-pixel variation.
            let bucket = (line.fontSize * 10).rounded() / 10
            histogram[bucket, default: 0] += line.text.count
        }
        return histogram.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key ?? 12
    }

    private static func indentLevel(
        for line: TextLine,
        relativeTo minimumIndent: Double,
        bodyFontSize: Double
    ) -> Int {
        let step = max(bodyFontSize, 1) * 1.5
        let offset = max(line.indent - minimumIndent, 0)
        return min(Int(offset / step), Self.maximumListIndentLevel)
    }

    private static func terminatesParagraph(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?".contains(last)
    }

    private static let maximumHeadingLength = 120
    private static let maximumListIndentLevel = 5
    private static let titleRatio = 1.6
    private static let majorHeadingRatio = 1.3
    private static let minorHeadingRatio = 1.12
}

/// Recognises list markers at the start of a line.
enum ListMarker {

    struct Parsed: Equatable {
        var content: String
        var isOrdered: Bool
    }

    private static let bulletCharacters: Set<Character> = [
        "•", "◦", "▪", "▫", "‣", "⁃", "·", "–", "—", "*", "-", "+"
    ]

    /// Whether `text` is a list marker standing on its own, such as "1." or a
    /// lone bullet.
    ///
    /// A layout that puts markers in their own column reads as a table to a
    /// geometric scan, but is far more useful as a list.
    static func isBareMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 5 else { return false }

        if trimmed.count == 1, let only = trimmed.first, bulletCharacters.contains(only) {
            return true
        }

        var body = Substring(trimmed)
        if body.last == "." || body.last == ")" { body = body.dropLast() }
        guard !body.isEmpty else { return false }

        let isNumeric = body.allSatisfy(\.isNumber)
        let isRoman = body.lowercased().allSatisfy { "ivxlcdm".contains($0) }
        return isNumeric || isRoman
    }

    /// Parses a leading list marker from `line`.
    ///
    /// - Returns: The marker kind and remaining content, or `nil` when the line
    ///   does not begin with a recognised marker.
    static func parse(_ line: String) -> Parsed? {
        guard let first = line.first else { return nil }

        if bulletCharacters.contains(first) {
            let remainder = line.dropFirst().trimmingCharacters(in: .whitespaces)
            // A bare marker, or a hyphenated word such as "re-use", is not a list.
            guard !remainder.isEmpty, line.dropFirst().first?.isWhitespace == true else { return nil }
            return Parsed(content: remainder, isOrdered: false)
        }

        return parseOrdered(line)
    }

    /// Parses a leading `1.`, `1)`, `a.` or `iv.` style marker.
    private static func parseOrdered(_ line: String) -> Parsed? {
        let marker = line.prefix { $0.isNumber || $0.isLetter }
        guard !marker.isEmpty, marker.count <= 4 else { return nil }

        let rest = line.dropFirst(marker.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }

        let remainder = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty, rest.dropFirst().first?.isWhitespace == true else { return nil }

        // A single letter marker is ambiguous with an initial, so require that
        // numeric or roman numeral markers are used for ordered lists.
        let isNumeric = marker.allSatisfy(\.isNumber)
        let isRoman = marker.lowercased().allSatisfy { "ivxlcdm".contains($0) }
        guard isNumeric || isRoman else { return nil }

        return Parsed(content: remainder, isOrdered: true)
    }
}
