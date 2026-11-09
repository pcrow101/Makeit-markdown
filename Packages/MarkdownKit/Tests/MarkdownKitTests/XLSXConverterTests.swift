import Foundation
import Testing

@testable import MarkdownKit

@Suite("XLSXConverter")
struct XLSXConverterTests {

    private typealias Sheet = XLSXFixture.Sheet
    private typealias Cell = XLSXFixture.Cell

    private let converter = XLSXConverter()

    private func convert(
        _ sheets: [Sheet],
        options: ConversionOptions = .default,
        uses1904Dates: Bool = false,
        deflate: Bool = false
    ) async throws -> ConversionResult {
        let scratch = try PDFFixture.Scratch()
        let url = try XLSXFixture.write(
            sheets: sheets,
            in: scratch.directory,
            uses1904Dates: uses1904Dates,
            deflate: deflate
        )
        return try await converter.convert(url: url, options: options)
    }

    // MARK: - Tables

    @Test("A sheet becomes a heading and a table with the first row as header")
    func basicTable() async throws {
        let result = try await convert([
            Sheet(name: "Fruit", rows: [
                [.text("Name"), .text("Qty")],
                [.text("Apple"), .number("3")],
                [.text("Pear"), .number("12")]
            ])
        ])

        #expect(result.markdown == """
            # Fruit

            | Name | Qty |
            | --- | --- |
            | Apple | 3 |
            | Pear | 12 |

            """)
        #expect(result.pageCount == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test("Several sheets appear in workbook order and hidden sheets are skipped")
    func multipleSheets() async throws {
        let result = try await convert([
            Sheet(name: "First", rows: [[.text("A")], [.text("1")]]),
            Sheet(name: "Secret", rows: [[.text("X")], [.text("9")]], isHidden: true),
            Sheet(name: "Third", rows: [[.text("B")], [.text("2")]])
        ])

        let first = try #require(result.markdown.range(of: "# First"))
        let third = try #require(result.markdown.range(of: "# Third"))
        #expect(first.lowerBound < third.lowerBound)
        #expect(!result.markdown.contains("Secret"))
    }

    @Test("An empty sheet is left out")
    func emptySheet() async throws {
        let result = try await convert([
            Sheet(name: "Blank", rows: [[.empty, .empty]]),
            Sheet(name: "Data", rows: [[.text("A")], [.text("1")]])
        ])

        #expect(!result.markdown.contains("Blank"))
        #expect(result.markdown.contains("# Data"))
    }

    @Test("Blank leading rows and columns are trimmed")
    func trimsBlankEdges() async throws {
        let result = try await convert([
            Sheet(name: "Offset", rows: [
                [],
                [],
                [.empty, .empty, .text("Name"), .text("Qty")],
                [.empty, .empty, .text("Apple"), .number("3")]
            ])
        ])

        #expect(result.markdown.contains("| Name | Qty |"))
        #expect(result.markdown.contains("| Apple | 3 |"))
    }

    @Test("Blank rows inside a sheet are dropped and gaps in a row stay empty")
    func gaps() async throws {
        let result = try await convert([
            Sheet(name: "Gaps", rows: [
                [.text("A"), .text("B"), .text("C")],
                [],
                [.text("1"), .empty, .text("3")]
            ])
        ])

        #expect(result.markdown.contains("| A | B | C |"))
        #expect(result.markdown.contains("| 1 |  | 3 |"))
    }

    @Test("Pipes and line breaks inside a cell cannot break the table")
    func escapesCells() async throws {
        let result = try await convert([
            Sheet(name: "Escapes", rows: [
                [.text("Text")],
                [.inline("left|right")],
                [.inline("one\ntwo")]
            ])
        ])

        #expect(result.markdown.contains("| left\\|right |"))
        #expect(result.markdown.contains("| one two |"))
    }

    @Test("Names with markup characters are written safely")
    func sheetNameIsEscaped() async throws {
        let result = try await convert([
            Sheet(name: "Q1 & Q2 <draft>", rows: [[.text("A")], [.text("1")]])
        ])

        #expect(result.markdown.contains("# Q1 & Q2 \\<draft\\>"))
    }

    // MARK: - Values

    @Test("Numbers are shown without floating point noise")
    func numbers() async throws {
        let result = try await convert([
            Sheet(name: "Numbers", rows: [
                [.text("Value")],
                [.number("0.30000000000000004")],
                [.number("1234.5000")],
                [.number("-7")],
                [.number("1E3")]
            ])
        ])

        #expect(result.markdown.contains("| 0.3 |"))
        #expect(result.markdown.contains("| 1234.5 |"))
        #expect(result.markdown.contains("| -7 |"))
        #expect(result.markdown.contains("| 1000 |"))
    }

    @Test("Dates and times are shown as dates")
    func dates() async throws {
        let result = try await convert([
            Sheet(name: "Dates", rows: [
                [.text("When")],
                [.date(45_000)],
                [.dateTime(45_000.75)]
            ])
        ])

        #expect(result.markdown.contains("| 2023-03-15 |"))
        #expect(result.markdown.contains("| 2023-03-15 18:00 |"))
    }

    @Test("The 1904 date system is honoured")
    func dates1904() async throws {
        let result = try await convert(
            [Sheet(name: "Dates", rows: [[.text("When")], [.date(0)]])],
            uses1904Dates: true
        )

        #expect(result.markdown.contains("| 1904-01-01 |"))
    }

    @Test("Percentages keep the precision of their format")
    func percentages() async throws {
        let result = try await convert([
            Sheet(name: "Rates", rows: [
                [.text("Rate")],
                [.percent("0.256")],
                [.customPercent("0.256")]
            ])
        ])

        #expect(result.markdown.contains("| 25.60% |"))
        #expect(result.markdown.contains("| 25.6% |"))
    }

    @Test("Booleans, formulas and errors show their stored values")
    func otherTypes() async throws {
        let result = try await convert([
            Sheet(name: "Mixed", rows: [
                [.text("Value")],
                [.boolean(true)],
                [.boolean(false)],
                [.formula("6")],
                [.error("#DIV/0!")]
            ])
        ])

        #expect(result.markdown.contains("| TRUE |"))
        #expect(result.markdown.contains("| FALSE |"))
        #expect(result.markdown.contains("| 6 |"))
        #expect(result.markdown.contains("| #DIV/0! |"))
    }

    @Test("Deflate compressed workbooks are read")
    func compressedWorkbook() async throws {
        let result = try await convert(
            [Sheet(name: "Packed", rows: [[.text("A")], [.text("1")]])],
            deflate: true
        )

        #expect(result.markdown.contains("| A |"))
    }

    // MARK: - Limits

    private func longSheet() -> Sheet {
        var rows: [[Cell]] = [[.text("N")]]
        rows += (1...5).map { [.number("\($0)")] }
        return Sheet(name: "Long", rows: rows)
    }

    @Test("Rows beyond the limit are dropped with a warning")
    func rowLimit() async throws {
        let result = try await convert(
            [longSheet()],
            options: ConversionOptions(maxSpreadsheetRows: 2)
        )

        #expect(result.markdown.contains("| 2 |"))
        #expect(!result.markdown.contains("| 3 |"))

        let warning = try #require(result.warnings.first)
        #expect(warning.kind == .truncatedContent)
        #expect(warning.message.contains("Long"))
        #expect(warning.message.contains("3 more"))
    }

    @Test("The limit applies to each sheet separately")
    func limitIsPerSheet() async throws {
        let result = try await convert(
            [longSheet(), Sheet(name: "Short", rows: [[.text("N")], [.number("9")]])],
            options: ConversionOptions(maxSpreadsheetRows: 2)
        )

        #expect(result.markdown.contains("| 9 |"))
        #expect(result.warnings.count == 1)
    }

    @Test("A limit of zero keeps every row", arguments: [0, 5, 100])
    func noLimit(limit: Int) async throws {
        let result = try await convert(
            [longSheet()],
            options: ConversionOptions(maxSpreadsheetRows: limit)
        )

        #expect(result.markdown.contains("| 5 |"))
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Charts and pictures

    @Test("Charts and pictures are reported but not converted")
    func graphicsWarning() async throws {
        let result = try await convert([
            Sheet(name: "Report", rows: [[.text("A")], [.text("1")]], charts: 1, images: 2)
        ])

        let warning = try #require(result.warnings.first)
        #expect(warning.kind == .unsupportedFeature)
        #expect(warning.message.contains("1 chart and 2 pictures"))
        #expect(result.markdown.contains("| A |"))
    }

    @Test("A sheet holding only a chart still yields a warning")
    func chartOnlySheet() async throws {
        let result = try await convert([Sheet(name: "Chart", rows: [], charts: 1)])

        #expect(result.markdown.isEmpty)
        let warning = try #require(result.warnings.first)
        #expect(warning.message.contains("no other content"))
    }

    // MARK: - Failures

    @Test("A workbook with no content at all is reported")
    func emptyWorkbook() async throws {
        await #expect(throws: ConversionError.self) {
            try await convert([Sheet(name: "Blank", rows: [])])
        }
    }

    @Test("A file that is not a workbook is reported as unreadable")
    func notAWorkbook() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "broken.xlsx")
        try Data("this is not a workbook".utf8).write(to: url)

        await #expect(throws: ConversionError.unreadableDocument(
            url: url,
            reason: "the file is not a valid Excel workbook"
        )) {
            try await converter.convert(url: url, options: .default)
        }
    }

    @Test("A ZIP archive without a workbook part is reported as unreadable")
    func archiveWithoutWorkbook() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "other.xlsx")
        try XLSXFixture.zip([("readme.txt", Data("hello".utf8))]).write(to: url)

        await #expect(throws: ConversionError.self) {
            try await converter.convert(url: url, options: .default)
        }
    }

    @Test("A password protected workbook is reported as such")
    func passwordProtected() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "locked.xlsx")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]).write(to: url)

        await #expect(throws: ConversionError.passwordProtected(url: url)) {
            try await converter.convert(url: url, options: .default)
        }
    }
}
