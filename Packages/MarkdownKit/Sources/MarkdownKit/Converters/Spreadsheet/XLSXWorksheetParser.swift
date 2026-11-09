import Foundation

/// A cell position parsed from an `A1`-style reference.
struct XLSXCellReference: Equatable {

    /// Zero-based column index.
    let column: Int

    /// Zero-based row index.
    let row: Int

    /// The largest column and row Excel allows.
    static let maximumColumn = 16_384
    static let maximumRow = 1_048_576

    init?(_ text: String) {
        var column = 0
        var digits = ""

        for scalar in text.unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90 && digits.isEmpty {
                column = column * 26 + Int(scalar.value) - 64
            } else if scalar.value >= 97 && scalar.value <= 122 && digits.isEmpty {
                column = column * 26 + Int(scalar.value) - 96
            } else if scalar.value >= 48 && scalar.value <= 57 {
                digits.unicodeScalars.append(scalar)
            } else {
                return nil
            }
        }

        guard column >= 1, column <= Self.maximumColumn,
              let row = Int(digits), row >= 1, row <= Self.maximumRow else { return nil }
        self.column = column - 1
        self.row = row - 1
    }
}

/// Reads the cells of one worksheet.
///
/// Values are resolved to display text as they are read, so the parsed sheet
/// is a sparse grid of strings with no further lookups needed.
final class XLSXWorksheetParser: NSObject, XMLParserDelegate {

    /// Non-empty cell text keyed by zero-based row, then column.
    private(set) var cells: [Int: [Int: String]] = [:]

    /// The relationship identifier of the sheet's drawing, if it has one.
    private(set) var drawingRelationshipID: String?

    private enum Capture {
        case value
        case inlineText
    }

    private let sharedStrings: [String]
    private let styles: XLSXStyles
    private let uses1904Dates: Bool

    private var row = -1
    private var column = -1
    private var cellType = ""
    private var cellStyle = 0
    private var value = ""
    private var inlineText = ""
    private var capture: Capture?
    private var isInsideInlineString = false
    private var isInsidePhonetic = false

    init(sharedStrings: [String], styles: XLSXStyles, uses1904Dates: Bool) {
        self.sharedStrings = sharedStrings
        self.styles = styles
        self.uses1904Dates = uses1904Dates
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "row":
            row = attributeDict["r"].flatMap(Int.init).map { $0 - 1 } ?? row + 1
            column = -1
        case "c":
            beginCell(attributeDict)
        case "v":
            capture = .value
        case "is":
            isInsideInlineString = true
        case "rPh":
            isInsidePhonetic = true
        case "t" where isInsideInlineString && !isInsidePhonetic:
            capture = .inlineText
        case "drawing":
            drawingRelationshipID = XLSXXML.attribute("id", in: attributeDict)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch capture {
        case .value: value += string
        case .inlineText: inlineText += string
        case nil: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v", "t": capture = nil
        case "is": isInsideInlineString = false
        case "rPh": isInsidePhonetic = false
        case "c": finishCell()
        default: break
        }
    }

    // MARK: - Cells

    private func beginCell(_ attributes: [String: String]) {
        if let reference = attributes["r"].flatMap(XLSXCellReference.init) {
            column = reference.column
            row = reference.row
        } else {
            column += 1
        }
        cellType = attributes["t"] ?? "n"
        cellStyle = attributes["s"].flatMap(Int.init) ?? 0
        value = ""
        inlineText = ""
    }

    private func finishCell() {
        let text = displayText()
        guard !text.isEmpty, row >= 0, column >= 0 else { return }
        cells[row, default: [:]][column] = text
    }

    private func displayText() -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch cellType {
        case "s":
            guard let index = Int(trimmed), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "inlineStr":
            return inlineText
        case "str", "e", "d":
            return value
        case "b":
            return trimmed.isEmpty ? "" : (trimmed == "1" ? "TRUE" : "FALSE")
        default:
            guard !trimmed.isEmpty else { return "" }
            return XLSXValueFormatter.string(
                for: trimmed,
                format: styles.format(forStyle: cellStyle),
                uses1904Dates: uses1904Dates
            )
        }
    }
}
