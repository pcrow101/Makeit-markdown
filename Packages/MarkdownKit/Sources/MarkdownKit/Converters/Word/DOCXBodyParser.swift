import Foundation

/// A paragraph as read from `word/document.xml`, before its role is known.
struct DOCXParagraph {
    var text = ""
    var styleID: String?
    var outlineLevel: Int?
    var numberingID: String?
    var numberingLevel: Int?
    /// Characters of the text set in a fixed-width font.
    var monospaceCount = 0
    /// Pictures in the paragraph, as `.image` blocks whose path is the
    /// picture's relationship ID.
    var images: [DocumentBlock] = []

    /// Whether most of the paragraph is set in a fixed-width font, as source
    /// code usually is.
    var isMonospace: Bool {
        let visible = text.filter { !$0.isWhitespace }.count
        return visible > 0 && monospaceCount * 10 >= visible * 6
    }
}

/// Reads the body of `word/document.xml` into paragraphs and tables.
///
/// The parser reports structure only. Paragraph roles are settled by
/// ``DOCXBodyAssembler`` once styles and numbering are known, and pictures are
/// reported by relationship ID for the reader to resolve.
final class DOCXBodyParser: NSObject, XMLParserDelegate {

    /// A block of the document body in reading order.
    enum Item {
        case paragraph(DOCXParagraph)
        case table(rows: [[String]])
        case image(DocumentBlock)
    }

    private struct Table {
        var rows: [[String]] = []
        var row: [String]?
        var cell: [DOCXParagraph]?
        var firstCell: [DOCXParagraph] = []
        var span = 1
        /// Pictures inside the table, shown after it.
        var images: [DocumentBlock] = []
    }

    private(set) var items: [Item] = []

    /// Charts found in the document, which are not converted.
    private(set) var chartCount = 0

    private var paragraphs: [DOCXParagraph] = []
    private var tables: [Table] = []
    private var isCapturingText = false
    private var isMonospaceRun = false
    private var ignoredDepth = 0
    private var propertiesChangeDepth = 0
    private var pictureDescription = ""

    private static let ignoredElements: Set<String> = [
        "mc:Fallback", "w:delText", "w:instrText", "w:del", "w:moveFrom"
    ]

    // MARK: - Elements

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        // Fallback content repeats the preceding choice in an older form, and
        // deleted or field code text is not part of the visible document.
        if Self.ignoredElements.contains(elementName) || ignoredDepth > 0 {
            if Self.ignoredElements.contains(elementName) { ignoredDepth += 1 }
            return
        }
        if elementName == "w:pPrChange" || elementName == "w:rPrChange" { propertiesChangeDepth += 1 }

        if startStructure(elementName, attributes: attributeDict) { return }
        if startProperty(elementName, attributes: attributeDict) { return }
        startContent(elementName, attributes: attributeDict)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if Self.ignoredElements.contains(elementName) {
            ignoredDepth = max(ignoredDepth - 1, 0)
            return
        }
        guard ignoredDepth == 0 else { return }

        switch elementName {
        case "w:pPrChange", "w:rPrChange": propertiesChangeDepth = max(propertiesChangeDepth - 1, 0)
        case "w:t": isCapturingText = false
        case "w:p": endParagraph()
        case "w:tc": endCell()
        case "w:tr": endRow()
        case "w:tbl": endTable()
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingText, ignoredDepth == 0, !paragraphs.isEmpty else { return }
        appendText(string)
        if isMonospaceRun {
            paragraphs[paragraphs.count - 1].monospaceCount += string.filter { !$0.isWhitespace }.count
        }
    }

    // MARK: - Structure

    private func startStructure(_ name: String, attributes: [String: String]) -> Bool {
        switch name {
        case "w:p":
            paragraphs.append(DOCXParagraph())
        case "w:r":
            isMonospaceRun = false
        case "w:tbl":
            tables.append(Table())
        case "w:tr":
            guard !tables.isEmpty else { return true }
            tables[tables.count - 1].row = []
        case "w:tc":
            guard !tables.isEmpty else { return true }
            tables[tables.count - 1].cell = []
            tables[tables.count - 1].span = 1
        case "w:gridSpan":
            guard !tables.isEmpty else { return true }
            let span = XLSXXML.attribute("val", in: attributes).flatMap(Int.init) ?? 1
            tables[tables.count - 1].span = min(max(span, 1), 64)
        default:
            return false
        }
        return true
    }

    /// Records paragraph properties (style, outline level and numbering) and
    /// whether a run uses a fixed-width font.
    private func startProperty(_ name: String, attributes: [String: String]) -> Bool {
        if name == "w:rFonts" {
            let font = XLSXXML.attribute("ascii", in: attributes)
                ?? XLSXXML.attribute("hAnsi", in: attributes)
            isMonospaceRun = font.map(Self.isMonospaceFont) ?? isMonospaceRun
            return true
        }
        guard ["w:pStyle", "w:outlineLvl", "w:numId", "w:ilvl"].contains(name) else { return false }
        guard propertiesChangeDepth == 0, !paragraphs.isEmpty else { return true }

        let value = XLSXXML.attribute("val", in: attributes)
        let index = paragraphs.count - 1
        switch name {
        case "w:pStyle": paragraphs[index].styleID = value
        case "w:outlineLvl": paragraphs[index].outlineLevel = value.flatMap(Int.init)
        case "w:numId": paragraphs[index].numberingID = value
        default: paragraphs[index].numberingLevel = value.flatMap(Int.init)
        }
        return true
    }

    static func isMonospaceFont(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["mono", "courier", "consolas", "menlo", "monaco", "console", "code"]
            .contains { lowered.contains($0) }
    }

    /// Records text and pictures.
    private func startContent(_ name: String, attributes: [String: String]) {
        switch name {
        case "w:t":
            isCapturingText = true
        case "w:tab", "w:ptab":
            // Tab stop definitions in paragraph properties share the name.
            if XLSXXML.attribute("pos", in: attributes) == nil { appendText(" ") }
        case "w:br", "w:cr":
            appendText(XLSXXML.attribute("type", in: attributes) == "page" ? " " : "\n")
        case "w:noBreakHyphen":
            appendText("-")
        case "w:drawing", "w:pict":
            pictureDescription = ""
        case "wp:docPr":
            pictureDescription = XLSXXML.attribute("descr", in: attributes)
                ?? XLSXXML.attribute("title", in: attributes) ?? ""
        case "a:blip":
            addPicture(XLSXXML.attribute("embed", in: attributes))
        case "v:imagedata":
            if let title = XLSXXML.attribute("title", in: attributes), !title.isEmpty {
                pictureDescription = title
            }
            addPicture(XLSXXML.attribute("id", in: attributes))
        case "c:chart":
            chartCount += 1
        default:
            break
        }
    }

    private func appendText(_ text: String) {
        guard !paragraphs.isEmpty else { return }
        paragraphs[paragraphs.count - 1].text += text
    }

    private func addPicture(_ relationshipID: String?) {
        guard let relationshipID, !relationshipID.isEmpty, !paragraphs.isEmpty else { return }
        paragraphs[paragraphs.count - 1].images.append(
            .image(path: relationshipID, altText: pictureDescription)
        )
    }

    // MARK: - Closing

    private func endParagraph() {
        guard let paragraph = paragraphs.popLast() else { return }

        // A paragraph in a table cell adds to the cell, and its pictures are
        // shown after the table.
        if !tables.isEmpty, tables[tables.count - 1].cell != nil {
            tables[tables.count - 1].cell?.append(paragraph)
            tables[tables.count - 1].images.append(contentsOf: paragraph.images)
            return
        }
        items.append(.paragraph(paragraph))
    }

    private func endCell() {
        guard !tables.isEmpty, let cell = tables[tables.count - 1].cell else { return }
        let text = cell
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let index = tables.count - 1
        if tables[index].rows.isEmpty && tables[index].row?.isEmpty == true {
            tables[index].firstCell = cell.map { paragraph in
                var withoutImages = paragraph
                withoutImages.images = []
                return withoutImages
            }
        }
        let padding = Array(repeating: "", count: tables[index].span - 1)
        tables[index].row?.append(text)
        tables[index].row?.append(contentsOf: padding)
        tables[index].cell = nil
    }

    private func endRow() {
        guard !tables.isEmpty, let row = tables[tables.count - 1].row else { return }
        tables[tables.count - 1].rows.append(row)
        tables[tables.count - 1].row = nil
    }

    private func endTable() {
        guard let table = tables.popLast() else { return }

        // A table nested in a cell is flattened into the outer cell's text.
        if !tables.isEmpty, tables[tables.count - 1].cell != nil {
            let text = table.rows.flatMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            tables[tables.count - 1].cell?.append(DOCXParagraph(text: text))
            tables[tables.count - 1].images.append(contentsOf: table.images)
            return
        }

        // A table of one cell is a box drawn around its content, such as a
        // code sample, rather than tabular data.
        if table.rows.count == 1, table.rows[0].count == 1 {
            let isCode = table.firstCell.contains(where: \.isMonospace)
            items.append(contentsOf: table.firstCell.map { paragraph in
                var boxed = paragraph
                if isCode { boxed.monospaceCount = paragraph.text.count }
                return .paragraph(boxed)
            })
        } else {
            items.append(.table(rows: table.rows))
        }
        items.append(contentsOf: table.images.map(Item.image))
    }
}
