import Foundation

/// Applies the conversion options to the blocks read from a word processing
/// document and tidies them for rendering.
///
/// Word documents state their structure explicitly, so the readers always
/// report headings, lists and tables. Turning an option off turns the matching
/// blocks back into plain paragraphs here, which keeps the options meaning the
/// same as they do for PDF documents.
enum WordBlockAdjuster {

    static func adjust(_ blocks: [DocumentBlock], options: ConversionOptions) -> [DocumentBlock] {
        var adjusted: [DocumentBlock] = []

        for block in blocks {
            for item in adjust(block, options: options) {
                append(item, to: &adjusted)
            }
        }
        return adjusted
    }

    private static func adjust(_ block: DocumentBlock, options: ConversionOptions) -> [DocumentBlock] {
        switch block {
        case .heading(let text, let level):
            let line = singleLine(text)
            guard !line.isEmpty else { return [] }
            return [options.detectHeadings ? .heading(text: line, level: level) : .paragraph(text: line)]

        case .listItem(let text, let ordered, let indentLevel):
            let line = singleLine(text)
            guard !line.isEmpty else { return [] }
            return [
                options.detectLists
                    ? .listItem(text: line, ordered: ordered, indentLevel: indentLevel)
                    : .paragraph(text: line)
            ]

        case .paragraph(let text), .blockQuote(let text):
            guard !singleLine(text).isEmpty else { return [] }
            return [block]

        case .codeBlock(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [block]

        case .table(let rows):
            return table(rows, options: options)

        case .image:
            return [block]
        }
    }

    /// A rectangular table without empty rows, or its rows as paragraphs when
    /// tables are turned off.
    private static func table(_ rows: [[String]], options: ConversionOptions) -> [DocumentBlock] {
        let cleaned = rows
            .map { $0.map(singleLine) }
            .filter { row in row.contains { !$0.isEmpty } }
        guard !cleaned.isEmpty else { return [] }

        guard options.extractTables else {
            return cleaned.map { row in
                .paragraph(text: row.filter { !$0.isEmpty }.joined(separator: " "))
            }
        }

        let width = cleaned.map(\.count).max() ?? 0
        let rectangular = cleaned.map { $0 + Array(repeating: "", count: width - $0.count) }
        return [.table(rows: rectangular)]
    }

    /// Appends `block`, joining it to a preceding code block so a run of code
    /// paragraphs becomes one fenced block.
    private static func append(_ block: DocumentBlock, to blocks: inout [DocumentBlock]) {
        if case .codeBlock(let text) = block, case .codeBlock(let previous)? = blocks.last {
            blocks[blocks.count - 1] = .codeBlock(text: previous + "\n" + text)
            return
        }
        blocks.append(block)
    }

    /// `text` on one line, with runs of whitespace collapsed.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
