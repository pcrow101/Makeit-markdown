import Foundation

/// The content of one worksheet, ready to be written as a table.
struct XLSXSheetContent: Equatable {

    let name: String

    /// Rows of equal length. Rows with no content are omitted, and so are
    /// columns that are empty at the left edge.
    let rows: [[String]]

    /// How many charts and pictures the sheet's drawing holds.
    let chartCount: Int
    let imageCount: Int
}

/// Reads the worksheets of an `.xlsx` workbook.
enum XLSXWorkbookReader {

    /// Reads every visible worksheet, in workbook order.
    ///
    /// A sheet whose file is missing from the archive is skipped rather than
    /// failing the whole conversion.
    static func readSheets(from archive: ZipArchive) throws -> [XLSXSheetContent] {
        guard let workbookData = try archive.contents(of: "xl/workbook.xml") else {
            throw XLSXError.notAWorkbook
        }

        let workbook = XLSXWorkbookParser()
        try XLSXXML.parse(workbookData, with: workbook, part: "xl/workbook.xml")

        let relationships = try relationships(in: archive, at: "xl/_rels/workbook.xml.rels")
        let context = CellContext(
            sharedStrings: try readSharedStrings(from: archive),
            styles: try readStyles(from: archive),
            uses1904Dates: workbook.uses1904Dates
        )

        var sheets: [XLSXSheetContent] = []
        for reference in workbook.sheets where !reference.isHidden {
            let relationship = relationships.first { $0.identifier == reference.relationshipID }
            guard let relationship,
                  let sheet = try readSheet(
                    named: reference.name,
                    at: resolve(relationship.target, in: "xl/"),
                    from: archive,
                    context: context
                  ) else { continue }
            sheets.append(sheet)
        }
        return sheets
    }

    /// What is needed to turn a cell's stored value into display text.
    private struct CellContext {
        let sharedStrings: [String]
        let styles: XLSXStyles
        let uses1904Dates: Bool
    }

    // MARK: - Parts

    private static func readSharedStrings(from archive: ZipArchive) throws -> [String] {
        guard let data = try archive.contents(of: "xl/sharedStrings.xml") else { return [] }
        let parser = XLSXSharedStringsParser()
        try XLSXXML.parse(data, with: parser, part: "xl/sharedStrings.xml")
        return parser.strings
    }

    private static func readStyles(from archive: ZipArchive) throws -> XLSXStyles {
        guard let data = try archive.contents(of: "xl/styles.xml") else { return XLSXStyles() }
        let parser = XLSXStylesParser()
        try XLSXXML.parse(data, with: parser, part: "xl/styles.xml")
        return parser.styles
    }

    private static func relationships(
        in archive: ZipArchive,
        at path: String
    ) throws -> [XLSXRelationship] {
        guard let data = try archive.contents(of: path) else { return [] }
        let parser = XLSXRelationshipsParser()
        try XLSXXML.parse(data, with: parser, part: path)
        return parser.relationships
    }

    private static func readSheet(
        named name: String,
        at path: String,
        from archive: ZipArchive,
        context: CellContext
    ) throws -> XLSXSheetContent? {
        guard let data = try archive.contents(of: path) else { return nil }

        let parser = XLSXWorksheetParser(
            sharedStrings: context.sharedStrings,
            styles: context.styles,
            uses1904Dates: context.uses1904Dates
        )
        try XLSXXML.parse(data, with: parser, part: path)

        let drawing = try drawingContents(of: parser, sheetPath: path, in: archive)
        return XLSXSheetContent(
            name: name,
            rows: rows(from: parser.cells),
            chartCount: drawing.charts,
            imageCount: drawing.images
        )
    }

    /// Counts the charts and pictures a sheet's drawing refers to.
    private static func drawingContents(
        of parser: XLSXWorksheetParser,
        sheetPath: String,
        in archive: ZipArchive
    ) throws -> (charts: Int, images: Int) {
        guard let drawingID = parser.drawingRelationshipID else { return (0, 0) }

        let sheetRelationships = try relationships(in: archive, at: relationshipsPath(for: sheetPath))
        guard let drawing = sheetRelationships.first(where: { $0.identifier == drawingID }) else {
            return (0, 0)
        }

        let drawingPath = resolve(drawing.target, in: directory(of: sheetPath))
        let parts = try relationships(in: archive, at: relationshipsPath(for: drawingPath))

        return (
            parts.filter { $0.type.hasSuffix("/chart") }.count,
            parts.filter { $0.type.hasSuffix("/image") }.count
        )
    }

    // MARK: - Grid

    /// Builds a rectangular grid from sparse cells.
    ///
    /// Rows with nothing in them are dropped, which keeps a stray value far
    /// down a sheet from producing thousands of empty table rows.
    static func rows(from cells: [Int: [Int: String]]) -> [[String]] {
        let columns = cells.values.flatMap(\.keys)
        guard let first = columns.min(), let last = columns.max() else { return [] }

        return cells.keys.sorted().map { row in
            let values = cells[row] ?? [:]
            return (first...last).map { values[$0] ?? "" }
        }
    }

    // MARK: - Paths

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    private static func relationshipsPath(for path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return directory(of: path) + "_rels/" + name + ".rels"
    }

    /// Resolves a relationship target against the folder of the part that
    /// holds it. Targets starting with `/` are relative to the package root.
    static func resolve(_ target: String, in directory: String) -> String {
        let combined = target.hasPrefix("/") ? String(target.dropFirst()) : directory + target

        var parts: [Substring] = []
        for part in combined.split(separator: "/") {
            if part == ".." {
                _ = parts.popLast()
            } else if part != "." {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }
}
