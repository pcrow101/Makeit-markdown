import Compression
import Foundation

/// Builds `.xlsx` workbooks at test time, so tests state exactly which cells,
/// styles and drawings they depend on and no binary files are committed.
enum XLSXFixture {

    /// A cell in a fixture sheet.
    enum Cell {
        case empty
        /// Text stored in the shared strings table.
        case text(String)
        /// Text stored inline in the cell.
        case inline(String)
        /// A number written exactly as given.
        case number(String)
        case boolean(Bool)
        /// A formula with its cached numeric result.
        case formula(String)
        case error(String)
        /// A serial date displayed with the built-in short date format.
        case date(Double)
        /// A date and time displayed with the built-in date time format.
        case dateTime(Double)
        /// A fraction displayed with the built-in `0.00%` format.
        case percent(String)
        /// A number displayed with the custom `0.0%` format.
        case customPercent(String)
    }

    struct Sheet {
        var name: String
        var rows: [[Cell]]
        var isHidden = false
        var charts = 0
        var images = 0
    }

    private static let contentTypes = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    // MARK: - Workbook

    /// Writes a workbook and returns its location.
    static func write(
        sheets: [Sheet],
        named name: String = "book",
        in directory: URL,
        uses1904Dates: Bool = false,
        deflate: Bool = false
    ) throws -> URL {
        let url = directory.appending(path: "\(name).xlsx")
        try workbook(sheets: sheets, uses1904Dates: uses1904Dates, deflate: deflate).write(to: url)
        return url
    }

    static func workbook(
        sheets: [Sheet],
        uses1904Dates: Bool = false,
        deflate: Bool = false
    ) -> Data {
        var strings: [String] = []
        var parts: [(name: String, data: Data)] = []

        for (index, sheet) in sheets.enumerated() {
            let number = index + 1
            parts.append(("xl/worksheets/sheet\(number).xml", Data(sheetXML(sheet, strings: &strings).utf8)))
            if sheet.charts + sheet.images > 0 {
                parts += drawingParts(for: sheet, number: number)
            }
        }

        parts.append(("xl/workbook.xml", Data(workbookXML(sheets, uses1904Dates).utf8)))
        parts.append(("xl/_rels/workbook.xml.rels", Data(workbookRelationships(count: sheets.count).utf8)))
        parts.append(("xl/styles.xml", Data(stylesXML.utf8)))
        parts.append(("xl/sharedStrings.xml", Data(sharedStringsXML(strings).utf8)))

        return zip(parts, deflate: deflate)
    }

    // MARK: - XML

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func workbookXML(_ sheets: [Sheet], _ uses1904Dates: Bool) -> String {
        let entries = sheets.enumerated().map { index, sheet in
            let state = sheet.isHidden ? " state=\"hidden\"" : ""
            return "<sheet name=\"\(escape(sheet.name))\" sheetId=\"\(index + 1)\"\(state) "
                + "r:id=\"rId\(index + 1)\"/>"
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <workbook xmlns="\(spreadsheet)" xmlns:r="\(contentTypes)">\
            <workbookPr\(uses1904Dates ? " date1904=\"1\"" : "")/>\
            <sheets>\(entries.joined())</sheets></workbook>
            """
    }

    private static func workbookRelationships(count: Int) -> String {
        let entries = (1...max(count, 1)).map {
            "<Relationship Id=\"rId\($0)\" Type=\"\(contentTypes)/worksheet\" "
                + "Target=\"worksheets/sheet\($0).xml\"/>"
        }
        return "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + entries.joined() + "</Relationships>"
    }

    /// Style 0 is general; 1 short date; 2 `0.00%`; 3 date time; 4 custom `0.0%`.
    private static let stylesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <styleSheet xmlns="\(spreadsheet)">\
        <numFmts count="1"><numFmt numFmtId="164" formatCode="0.0%"/></numFmts>\
        <cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs>\
        <cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="10"/>\
        <xf numFmtId="22"/><xf numFmtId="164"/></cellXfs></styleSheet>
        """

    private static func sharedStringsXML(_ strings: [String]) -> String {
        let items = strings.map { "<si><t xml:space=\"preserve\">\(escape($0))</t></si>" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"\(spreadsheet)\">"
            + items.joined() + "</sst>"
    }

    private static func sheetXML(_ sheet: Sheet, strings: inout [String]) -> String {
        var rows = ""
        for (rowIndex, cells) in sheet.rows.enumerated() {
            let xml = cells.enumerated().compactMap { column, cell in
                cellXML(cell, reference: reference(column: column, row: rowIndex), strings: &strings)
            }
            if !xml.isEmpty {
                rows += "<row r=\"\(rowIndex + 1)\">" + xml.joined() + "</row>"
            }
        }
        let drawing = sheet.charts + sheet.images > 0 ? "<drawing r:id=\"rId1\"/>" : ""
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<worksheet xmlns=\"\(spreadsheet)\" xmlns:r=\"\(contentTypes)\">"
            + "<sheetData>\(rows)</sheetData>\(drawing)</worksheet>"
    }

    private static func reference(column: Int, row: Int) -> String {
        var letters = ""
        var value = column + 1
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + remainder))) + letters
            value = (value - 1) / 26
        }
        return "\(letters)\(row + 1)"
    }

    private static func cellXML(_ cell: Cell, reference: String, strings: inout [String]) -> String? {
        let head = "<c r=\"\(reference)\""
        switch cell {
        case .empty:
            return nil
        case .text(let text):
            strings.append(text)
            return "\(head) t=\"s\"><v>\(strings.count - 1)</v></c>"
        case .inline(let text):
            return "\(head) t=\"inlineStr\"><is><t>\(escape(text))</t></is></c>"
        case .number(let value):
            return "\(head)><v>\(value)</v></c>"
        case .boolean(let flag):
            return "\(head) t=\"b\"><v>\(flag ? 1 : 0)</v></c>"
        case .formula(let value):
            return "\(head)><f>SUM(A1:A2)</f><v>\(value)</v></c>"
        case .error(let code):
            return "\(head) t=\"e\"><v>\(code)</v></c>"
        case .date(let serial):
            return "\(head) s=\"1\"><v>\(serial)</v></c>"
        case .dateTime(let serial):
            return "\(head) s=\"3\"><v>\(serial)</v></c>"
        case .percent(let value):
            return "\(head) s=\"2\"><v>\(value)</v></c>"
        case .customPercent(let value):
            return "\(head) s=\"4\"><v>\(value)</v></c>"
        }
    }

    // MARK: - Drawings

    private static func drawingParts(for sheet: Sheet, number: Int) -> [(name: String, data: Data)] {
        let rels = "http://schemas.openxmlformats.org/package/2006/relationships"
        let sheetRels = "<Relationships xmlns=\"\(rels)\"><Relationship Id=\"rId1\" "
            + "Type=\"\(contentTypes)/drawing\" Target=\"../drawings/drawing\(number).xml\"/></Relationships>"

        var entries: [String] = []
        for index in 0..<sheet.charts {
            entries.append("<Relationship Id=\"c\(index)\" Type=\"\(contentTypes)/chart\" "
                + "Target=\"../charts/chart\(index).xml\"/>")
        }
        for index in 0..<sheet.images {
            entries.append("<Relationship Id=\"i\(index)\" Type=\"\(contentTypes)/image\" "
                + "Target=\"../media/image\(index).png\"/>")
        }
        let drawingRels = "<Relationships xmlns=\"\(rels)\">" + entries.joined() + "</Relationships>"

        return [
            ("xl/worksheets/_rels/sheet\(number).xml.rels", Data(sheetRels.utf8)),
            ("xl/drawings/drawing\(number).xml", Data("<xdr:wsDr/>".utf8)),
            ("xl/drawings/_rels/drawing\(number).xml.rels", Data(drawingRels.utf8))
        ]
    }

    // MARK: - ZIP

    /// Builds a ZIP archive. Checksums are left at zero because the reader
    /// does not verify them.
    static func zip(_ parts: [(name: String, data: Data)], deflate: Bool = false) -> Data {
        var archive = Data()
        var directory = Data()

        for part in parts {
            let name = Data(part.name.utf8)
            let method = deflate ? 8 : 0
            let payload = deflate ? compress(part.data) : part.data
            let offset = archive.count

            archive.append(le: 0x0403_4B50, width: 4)
            archive.append(le: 20, width: 2)
            archive.append(le: 0, width: 2)
            archive.append(le: method, width: 2)
            archive.append(le: 0, width: 4)
            archive.append(le: 0, width: 4)
            archive.append(le: payload.count, width: 4)
            archive.append(le: part.data.count, width: 4)
            archive.append(le: name.count, width: 2)
            archive.append(le: 0, width: 2)
            archive.append(name)
            archive.append(payload)

            directory.append(le: 0x0201_4B50, width: 4)
            directory.append(le: 20, width: 2)
            directory.append(le: 20, width: 2)
            directory.append(le: 0, width: 2)
            directory.append(le: method, width: 2)
            directory.append(le: 0, width: 4)
            directory.append(le: 0, width: 4)
            directory.append(le: payload.count, width: 4)
            directory.append(le: part.data.count, width: 4)
            directory.append(le: name.count, width: 2)
            // Extra, comment, disk and internal attribute fields, then external.
            directory.append(le: 0, width: 8)
            directory.append(le: 0, width: 4)
            directory.append(le: offset, width: 4)
            directory.append(name)
        }

        var end = Data()
        end.append(le: 0x0605_4B50, width: 4)
        end.append(le: 0, width: 4)
        end.append(le: parts.count, width: 2)
        end.append(le: parts.count, width: 2)
        end.append(le: directory.count, width: 4)
        end.append(le: archive.count, width: 4)
        end.append(le: 0, width: 2)

        return archive + directory + end
    }

    private static func compress(_ data: Data) -> Data {
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: source.count + 1_024)
        let size = compression_encode_buffer(
            &destination,
            destination.count,
            source,
            source.count,
            nil,
            COMPRESSION_ZLIB
        )
        return Data(destination.prefix(size))
    }
}

extension Data {

    /// Appends `value` as a little-endian integer of `width` bytes.
    fileprivate mutating func append(le value: Int, width: Int) {
        for index in 0..<width {
            append(UInt8(truncatingIfNeeded: value >> (8 * index)))
        }
    }
}
