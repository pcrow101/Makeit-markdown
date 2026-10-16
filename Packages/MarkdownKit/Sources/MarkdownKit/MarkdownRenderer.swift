import Foundation

/// Renders structural blocks into a Markdown document.
///
/// Consecutive list items at the same depth are merged into a single list so
/// the output nests correctly rather than producing a run of one-item lists.
public struct MarkdownRenderer: Sendable {

    private let options: ConversionOptions

    public init(options: ConversionOptions) {
        self.options = options
    }

    /// Renders `pages` into a single Markdown document.
    ///
    /// - Parameter pages: Blocks grouped by source page, in reading order.
    public func render(pages: [[DocumentBlock]]) -> String {
        var builder = MarkdownBuilder()

        for (index, blocks) in pages.enumerated() where !blocks.isEmpty {
            if options.insertPageBreaks && index > 0 {
                builder.addThematicBreak()
            }
            append(blocks: blocks, to: &builder)
        }

        let markdown = builder.build()
        return options.normalizeWhitespace ? Self.normalize(markdown) : markdown
    }

    /// Renders a single sequence of blocks into Markdown.
    public func render(blocks: [DocumentBlock]) -> String {
        render(pages: [blocks])
    }

    private func append(blocks: [DocumentBlock], to builder: inout MarkdownBuilder) {
        var pendingItems: [String] = []
        var pendingOrdered = false
        var pendingIndent = 0

        func flushList() {
            guard !pendingItems.isEmpty else { return }
            builder.addList(pendingItems, ordered: pendingOrdered, indentLevel: pendingIndent)
            pendingItems.removeAll(keepingCapacity: true)
        }

        for block in blocks {
            switch block {
            case .heading(let text, let level):
                flushList()
                builder.addHeading(text, level: level)

            case .paragraph(let text):
                flushList()
                builder.addParagraph(text)

            case .listItem(let text, let ordered, let indentLevel):
                if ordered != pendingOrdered || indentLevel != pendingIndent {
                    flushList()
                    pendingOrdered = ordered
                    pendingIndent = indentLevel
                }
                pendingItems.append(text)

            case .table(let rows):
                flushList()
                guard let headers = rows.first else { continue }
                builder.addTable(headers: headers, rows: Array(rows.dropFirst()))
            }
        }

        flushList()
    }

    /// Collapses runs of more than one blank line and trims trailing whitespace.
    private static func normalize(_ markdown: String) -> String {
        var output: [String] = []
        var previousWasBlank = false

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
            let isBlank = trimmed.isEmpty

            if isBlank && previousWasBlank { continue }
            output.append(trimmed)
            previousWasBlank = isBlank
        }

        while output.last?.isEmpty == true {
            output.removeLast()
        }

        guard !output.isEmpty else { return "" }
        return output.joined(separator: "\n") + "\n"
    }
}
