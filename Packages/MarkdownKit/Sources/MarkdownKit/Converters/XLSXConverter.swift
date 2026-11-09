import Foundation
import UniformTypeIdentifiers

/// Converts Excel workbooks (`.xlsx`) into Markdown tables.
///
/// The Open XML package is read directly, so no spreadsheet application is
/// needed. Each visible worksheet becomes a heading followed by a table whose
/// first row is the header. Formulas show their last calculated value, since
/// the converter never recalculates. Charts and pictures are not converted; a
/// warning names the sheets that hold them.
public struct XLSXConverter: DocumentConverter {

    public let formatName = "Excel"

    public var supportedTypes: [UTType] {
        // Declared by the system, so it is looked up rather than imported,
        // which would need an Info.plist declaration.
        [UTType("org.openxmlformats.spreadsheetml.sheet")].compactMap { $0 }
    }

    public init() {}

    public func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        try Task.checkCancellation()

        let sheets = try Self.readSheets(at: url)

        var blocks: [DocumentBlock] = []
        var warnings: [ConversionWarning] = []

        for sheet in sheets {
            try Task.checkCancellation()

            warnings.append(contentsOf: Self.graphicsWarnings(for: sheet))
            guard !sheet.rows.isEmpty else { continue }

            let (rows, dropped) = Self.truncated(sheet.rows, limit: options.maxSpreadsheetRows)
            if dropped > 0 {
                warnings.append(Self.truncationWarning(
                    sheet: sheet.name,
                    dropped: dropped,
                    kept: rows.count - 1
                ))
            }

            blocks.append(.heading(text: sheet.name, level: 1))
            blocks.append(.table(rows: rows))
        }

        if blocks.isEmpty && warnings.isEmpty {
            throw ConversionError.noExtractableText(url: url)
        }

        return ConversionResult(
            markdown: MarkdownRenderer(options: options).render(blocks: blocks),
            sourceURL: url,
            pageCount: sheets.count,
            warnings: warnings
        )
    }

    // MARK: - Reading

    private static func readSheets(at url: URL) throws -> [XLSXSheetContent] {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ConversionError.unreadableDocument(url: url, reason: error.localizedDescription)
        }

        // Excel stores a password protected workbook in an older container
        // rather than as a ZIP archive.
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
            throw ConversionError.passwordProtected(url: url)
        }

        do {
            return try XLSXWorkbookReader.readSheets(from: ZipArchive(data: data))
        } catch let error as ZipArchiveError {
            throw conversionError(for: error, url: url)
        } catch let error as XLSXError {
            throw conversionError(for: error, url: url)
        }
    }

    private static func conversionError(for error: ZipArchiveError, url: URL) -> ConversionError {
        switch error {
        case .encrypted:
            return .passwordProtected(url: url)
        case .notAnArchive:
            return .unreadableDocument(url: url, reason: "the file is not a valid Excel workbook")
        case .entryTooLarge:
            return .unreadableDocument(url: url, reason: "the workbook is too large to read")
        case .corrupt, .unsupportedCompression, .unsupportedZip64:
            return .unreadableDocument(
                url: url,
                reason: "the workbook is damaged or uses an unsupported format"
            )
        }
    }

    private static func conversionError(for error: XLSXError, url: URL) -> ConversionError {
        switch error {
        case .notAWorkbook:
            return .unreadableDocument(url: url, reason: "the file is not a valid Excel workbook")
        case .malformedXML(let part):
            return .unreadableDocument(url: url, reason: "\(part) in the workbook is not valid")
        }
    }

    // MARK: - Limits and warnings

    /// Applies the per sheet row limit, which counts rows below the header.
    /// A limit of zero means no limit.
    private static func truncated(_ rows: [[String]], limit: Int) -> (rows: [[String]], dropped: Int) {
        guard limit > 0, rows.count - 1 > limit else { return (rows, 0) }
        return (Array(rows.prefix(limit + 1)), rows.count - 1 - limit)
    }

    private static func truncationWarning(sheet: String, dropped: Int, kept: Int) -> ConversionWarning {
        ConversionWarning(
            kind: .truncatedContent,
            message: "Sheet “\(sheet)” was cut to its first \(kept) rows; \(dropped) more were left out."
        )
    }

    private static func graphicsWarnings(for sheet: XLSXSheetContent) -> [ConversionWarning] {
        var items: [String] = []
        if sheet.chartCount > 0 {
            items.append(sheet.chartCount == 1 ? "1 chart" : "\(sheet.chartCount) charts")
        }
        if sheet.imageCount > 0 {
            items.append(sheet.imageCount == 1 ? "1 picture" : "\(sheet.imageCount) pictures")
        }
        guard !items.isEmpty else { return [] }

        let suffix = sheet.rows.isEmpty ? " The sheet has no other content." : ""
        return [
            ConversionWarning(
                kind: .unsupportedFeature,
                message: "Sheet “\(sheet.name)” contains \(items.joined(separator: " and ")), "
                    + "which are not converted." + suffix
            )
        ]
    }
}
