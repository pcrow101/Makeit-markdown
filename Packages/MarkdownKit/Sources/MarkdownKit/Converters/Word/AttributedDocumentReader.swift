import AppKit
import Foundation

/// Reads a styled text document, such as a binary Word 97–2003 file or RTF,
/// into document blocks using AppKit's document readers.
///
/// These formats carry fonts rather than named styles, so headings are found
/// from font size and weight, like they are for PDF documents. Lists and tables
/// come from the paragraph styles AppKit attaches to the text.
enum AttributedDocumentReader {

    /// Opens `data` as a document of `type`, returning `nil` when AppKit cannot
    /// read it.
    static func attributedString(
        from data: Data,
        type: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: type],
            documentAttributes: nil
        )
    }

    /// The blocks of `text`, saving embedded pictures in `images`.
    static func blocks(
        from text: NSAttributedString,
        options: ConversionOptions,
        images: inout WordImageStore
    ) -> [DocumentBlock] {
        let paragraphs = Self.paragraphs(in: text)
        let bodyFontSize = DocumentStructureAnalyzer.modalFontSize(
            of: paragraphs.filter { $0.table == nil }.map(\.line)
        )
        let analyzer = DocumentStructureAnalyzer(options: options)

        var blocks: [DocumentBlock] = []
        var table: TableGrid?

        for paragraph in paragraphs {
            if let cell = paragraph.table {
                if table?.identifier != cell.identifier {
                    if let finished = table { blocks.append(finished.block) }
                    table = TableGrid(identifier: cell.identifier)
                }
                table?.add(paragraph.line.text, row: cell.row, column: cell.column)
            } else {
                if let finished = table { blocks.append(finished.block) }
                table = nil
                blocks.append(contentsOf: Self.blocks(
                    for: paragraph,
                    analyzer: analyzer,
                    bodyFontSize: bodyFontSize
                ))
            }
            for data in paragraph.attachments {
                let key = "attachment-\(images.assets.count + 1)"
                if let image = images.block(for: data, key: key, altText: "") { blocks.append(image) }
            }
        }
        if let finished = table { blocks.append(finished.block) }
        return blocks
    }

    // MARK: - Paragraphs

    private struct FontKey: Hashable {
        let size: Double
        let isBold: Bool
    }

    private struct CellPosition {
        let identifier: ObjectIdentifier
        let row: Int
        let column: Int
    }

    private struct Paragraph {
        var line: TextLine
        var list: (ordered: Bool, depth: Int)?
        var table: CellPosition?
        var attachments: [Data]
    }

    private static func blocks(
        for paragraph: Paragraph,
        analyzer: DocumentStructureAnalyzer,
        bodyFontSize: Double
    ) -> [DocumentBlock] {
        if let list = paragraph.list {
            return [.listItem(text: paragraph.line.text, ordered: list.ordered, indentLevel: list.depth)]
        }
        return analyzer.analyze(lines: [paragraph.line], bodyFontSize: bodyFontSize)
    }

    private static func paragraphs(in text: NSAttributedString) -> [Paragraph] {
        let string = text.string as NSString
        var result: [Paragraph] = []

        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: .byParagraphs
        ) { substring, range, _, _ in
            guard let substring, range.length > 0 else { return }
            result.append(paragraph(substring, range: range, in: text))
        }
        return result
    }

    private static func paragraph(
        _ substring: String,
        range: NSRange,
        in text: NSAttributedString
    ) -> Paragraph {
        let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            as? NSParagraphStyle
        var content = substring.replacingOccurrences(of: "\u{FFFC}", with: "")

        var list: (Bool, Int)?
        if let lists = style?.textLists, let innermost = lists.last {
            list = (isOrdered(innermost), lists.count - 1)
            content = strippingListMarker(content)
        }

        var cell: CellPosition?
        if let block = style?.textBlocks.first as? NSTextTableBlock {
            cell = CellPosition(
                identifier: ObjectIdentifier(block.table),
                row: block.startingRow,
                column: block.startingColumn
            )
        }

        let (fontSize, isBold) = dominantFont(in: text, range: range)
        return Paragraph(
            line: TextLine(
                text: content.trimmingCharacters(in: .whitespaces),
                fontSize: fontSize,
                isBold: isBold
            ),
            list: list,
            table: cell,
            attachments: attachments(in: text, range: range)
        )
    }

    /// The size and weight of the font covering most of `range`.
    private static func dominantFont(in text: NSAttributedString, range: NSRange) -> (Double, Bool) {
        var lengths: [FontKey: Int] = [:]
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            let key = FontKey(
                size: Double(font.pointSize),
                isBold: font.fontDescriptor.symbolicTraits.contains(.bold)
            )
            lengths[key, default: 0] += run.length
        }
        guard let dominant = lengths.max(by: { $0.value < $1.value })?.key else { return (12, false) }
        return (dominant.size, dominant.isBold)
    }

    private static func attachments(in text: NSAttributedString, range: NSRange) -> [Data] {
        var found: [Data] = []
        text.enumerateAttribute(.attachment, in: range) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents {
                found.append(data)
            }
        }
        return found
    }

    /// Whether a list's marker is a number or letter rather than a bullet.
    private static func isOrdered(_ list: NSTextList) -> Bool {
        let bullets = ["disc", "circle", "square", "hyphen", "check", "diamond", "box"]
        let format = list.markerFormat.rawValue.lowercased()
        return !bullets.contains { format.contains($0) }
    }

    /// Removes the tab-delimited marker AppKit writes at the start of a list
    /// item, such as `\t•\t` or `\t1.\t`.
    private static func strippingListMarker(_ text: String) -> String {
        guard text.hasPrefix("\t") else { return text }
        let rest = text.dropFirst()
        guard let tab = rest.firstIndex(of: "\t") else { return text }
        return String(rest[rest.index(after: tab)...])
    }
}

/// The cells of a table read from a styled text document.
private struct TableGrid {

    let identifier: ObjectIdentifier
    private var cells: [Int: [Int: [String]]] = [:]

    init(identifier: ObjectIdentifier) {
        self.identifier = identifier
    }

    mutating func add(_ text: String, row: Int, column: Int) {
        cells[row, default: [:]][column, default: []].append(text)
    }

    var block: DocumentBlock {
        let width = (cells.values.flatMap(\.keys).max() ?? -1) + 1
        let rows = cells.keys.sorted().map { row in
            (0..<width).map { column in
                (cells[row]?[column] ?? []).filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        return .table(rows: rows)
    }
}
