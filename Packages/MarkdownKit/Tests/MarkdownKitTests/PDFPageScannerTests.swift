import CoreGraphics
import Testing

@testable import MarkdownKit

@Suite("PDFPageScanner")
struct PDFPageScannerTests {

    private let converter = PDFConverter()

    private var tableOptions: ConversionOptions {
        ConversionOptions(experimentalTableExtraction: true)
    }

    @Test("A grid of cells becomes a Markdown table")
    func detectsTable() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            tableRows: [
                ["Ticket", "Summary", "Status"],
                ["AB-1", "First issue", "Open"],
                ["AB-2", "Second issue", "Closed"],
                ["AB-3", "Third issue", "Open"]
            ],
            named: "table",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: tableOptions)

        // A Markdown table is recognisable by its delimiter row.
        #expect(result.markdown.contains("| --- |"))
        #expect(result.markdown.contains("Ticket"))
        #expect(result.markdown.contains("AB-2"))
        #expect(result.markdown.contains("Closed"))
    }

    @Test("Every cell of a row appears on one Markdown row")
    func keepsRowsTogether() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            tableRows: [
                ["Key", "Owner"],
                ["AB-1", "Alice"],
                ["AB-2", "Bob"]
            ],
            named: "rows",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: tableOptions)
        let rows = result.markdown
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("|") && !$0.contains("---") }

        #expect(rows.contains { $0.contains("AB-1") && $0.contains("Alice") })
        #expect(rows.contains { $0.contains("AB-2") && $0.contains("Bob") })
        // Values from different rows must never share a line.
        #expect(!rows.contains { $0.contains("Alice") && $0.contains("Bob") })
    }

    @Test("Tables are not produced unless they are asked for")
    func disabledByDefault() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            tableRows: [
                ["Ticket", "Summary"],
                ["AB-1", "First issue"],
                ["AB-2", "Second issue"]
            ],
            named: "default",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(!result.markdown.contains("| --- |"))
    }

    @Test("Prose is not mistaken for a table")
    func prosePagesAreNotTables() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [
                PDFFixture.Line("A Document Title", fontSize: 20, isBold: true),
                PDFFixture.Line("The opening paragraph runs to a reasonable length."),
                PDFFixture.Line("A second paragraph follows it, also of some length."),
                PDFFixture.Line("A third paragraph closes the section.")
            ],
            named: "prose",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: tableOptions)

        #expect(!result.markdown.contains("| --- |"))
        #expect(result.markdown.contains("A Document Title"))
    }

    @Test("Headings and paragraphs survive when tables are enabled")
    func structureIsPreserved() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [
                PDFFixture.Line("Report", fontSize: 24, isBold: true),
                PDFFixture.Line("An introductory paragraph of ordinary prose."),
                PDFFixture.Line("• First point"),
                PDFFixture.Line("• Second point")
            ],
            named: "structure",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: tableOptions)

        #expect(result.markdown.contains("# Report"))
        #expect(result.markdown.contains("- First point"))
        #expect(result.markdown.contains("- Second point"))
    }

    // MARK: - Row breaks

    @Test("Evenly spaced lines each become a row")
    func uniformGapsGiveOneRowPerLine() {
        // Nothing wrapped, so there is no smaller gap to contrast with.
        #expect(PDFPageScanner.rowBreakThreshold(for: [28, 28, 28], lineHeight: 10) == 0)
    }

    @Test("A threshold falls between wrapped lines and row spacing")
    func separatesWrappedLinesFromRows() {
        let threshold = PDFPageScanner.rowBreakThreshold(
            for: [8.2, 8.1, 17.4, 8.2],
            lineHeight: 7
        )

        #expect(threshold > 8.2)
        #expect(threshold < 17.4)
    }

    @Test("One unusually wide gap does not raise the threshold")
    func toleratesAnOutlyingGap() {
        // A break before a sub heading is far wider than the row spacing. Taking
        // the widest jump would put the threshold above 17 and merge every row.
        let threshold = PDFPageScanner.rowBreakThreshold(
            for: [8, 8, 17, 17, 8, 60],
            lineHeight: 7
        )

        #expect(threshold > 8)
        #expect(threshold < 17)
    }

    @Test("Row spacing is not mistaken for wrapping")
    func requiresWrappedLinesToLookWrapped() {
        // Nothing wraps here; the wide gap is a section break. The ordinary row
        // spacing of 17 is too far apart to be lines within one cell.
        #expect(PDFPageScanner.rowBreakThreshold(for: [17, 17, 17, 60], lineHeight: 10) == 0)
    }

    @Test("Too few gaps to compare leaves lines separate")
    func handlesTooFewGaps() {
        #expect(PDFPageScanner.rowBreakThreshold(for: [], lineHeight: 10) == 0)
        #expect(PDFPageScanner.rowBreakThreshold(for: [12], lineHeight: 10) == 0)
    }

    @Test("Rows are not merged when cells wrap")
    func keepsWrappedRowsApart() async throws {
        let scratch = try PDFFixture.Scratch()
        // Each row has a cell that wraps onto a second line.
        let url = try PDFFixture.write(
            tableRows: [
                ["Event", "Meaning"],
                ["Break Start", "Sent when the advertisement break begins"],
                ["Break End", "Sent when the advertisement break finishes"],
                ["Break Error", "Sent when the advertisement break fails"]
            ],
            columnWidth: 150,
            named: "wrapped",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: tableOptions)
        let body = result.markdown
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("|") && !$0.contains("---") }

        // Each event must stay on its own row rather than being run together.
        #expect(body.contains { $0.contains("Break Start") && !$0.contains("Break End") })
        #expect(body.contains { $0.contains("Break End") && !$0.contains("Break Start") })
        #expect(body.contains { $0.contains("Break Error") && !$0.contains("Break End") })
    }

    @Test("Pieces sharing a line are ordered left to right")
    func ordersTiedFragmentsByPosition() {
        let left = PDFPageScanner.Fragment(
            text: "left",
            rect: CGRect(x: 10, y: 100, width: 20, height: 10),
            fontSize: 10,
            isBold: false
        )
        let right = PDFPageScanner.Fragment(
            text: "right",
            rect: CGRect(x: 80, y: 100, width: 20, height: 10),
            fontSize: 10,
            isBold: false
        )
        let below = PDFPageScanner.Fragment(
            text: "below",
            rect: CGRect(x: 10, y: 80, width: 20, height: 10),
            fontSize: 10,
            isBold: false
        )

        #expect(PDFPageScanner.readsBefore(left, right))
        #expect(!PDFPageScanner.readsBefore(right, left))
        // A higher line always comes first, whatever the horizontal position.
        #expect(PDFPageScanner.readsBefore(right, below))
    }

    // MARK: - Plausibility

    @Test("A populated grid is accepted")
    func acceptsPopulatedGrid() {
        #expect(PDFPageScanner.isTable([["Key", "Status"], ["AB-1", "Open"]]))
    }

    @Test("A grid with a single row is rejected")
    func rejectsSingleRow() {
        #expect(!PDFPageScanner.isTable([["Key", "Status"]]))
    }

    @Test("A mostly empty grid is rejected")
    func rejectsSparseGrid() {
        // A region that gathered unrelated content leaves most cells empty.
        let sparse = [
            ["Heading", "", "", "", "", ""],
            ["Body", "", "", "", "", ""]
        ]
        #expect(!PDFPageScanner.isTable(sparse))
    }

    @Test("A column of bare list markers is rejected")
    func rejectsMarkerColumn() {
        let list = [
            ["1.", "Target calculation"],
            ["2.", "Random selection"],
            ["3.", "Fills until complete"]
        ]
        #expect(!PDFPageScanner.isTable(list))
    }

    @Test("Numbered first cells that are not bare markers are kept")
    func keepsNumberedCells() {
        // Identifiers happen to start with digits but carry real content.
        let table = [
            ["AB-1", "First issue"],
            ["AB-2", "Second issue"]
        ]
        #expect(PDFPageScanner.isTable(table))
    }

    @Test("Bare markers are recognised, content is not")
    func bareMarkerRecognition() {
        #expect(ListMarker.isBareMarker("1."))
        #expect(ListMarker.isBareMarker("12)"))
        #expect(ListMarker.isBareMarker("iv."))
        #expect(ListMarker.isBareMarker("•"))
        #expect(!ListMarker.isBareMarker("AB-1"))
        #expect(!ListMarker.isBareMarker("Open"))
        #expect(!ListMarker.isBareMarker(""))
    }

    @Test("Rows holding no text are dropped")
    func prunesEmptyRows() {
        // A leading blank row would otherwise become the Markdown header.
        let pruned = PDFPageScanner.pruningEmptyRows([
            ["", "  ", ""],
            ["Key", "Status", "Owner"],
            ["AB-1", "Open", "Alice"],
            ["", "", ""]
        ])

        #expect(pruned.count == 2)
        #expect(pruned.first == ["Key", "Status", "Owner"])
    }

    @Test("A table of real content keeps every row")
    func keepsPopulatedRows() {
        let rows = [["Key", "Status"], ["AB-1", "Open"]]
        #expect(PDFPageScanner.pruningEmptyRows(rows) == rows)
    }

    // MARK: - Column pruning

    @Test("Columns that are empty throughout are dropped")
    func prunesEmptyColumns() {
        let pruned = PDFPageScanner.pruningEmptyColumns([
            ["Key", "", "Status", ""],
            ["AB-1", "", "Open", ""]
        ])

        #expect(pruned == [["Key", "Status"], ["AB-1", "Open"]])
    }

    @Test("A column holding any value at all is kept")
    func keepsPartiallyFilledColumns() {
        let pruned = PDFPageScanner.pruningEmptyColumns([
            ["Key", "Note", "Status"],
            ["AB-1", "", "Open"]
        ])

        #expect(pruned.first?.count == 3)
    }

    @Test("A fully occupied table is returned unchanged")
    func leavesFullTablesAlone() {
        let rows = [["A", "B"], ["C", "D"]]
        #expect(PDFPageScanner.pruningEmptyColumns(rows) == rows)
    }

    @Test("Pruning tolerates an empty table")
    func toleratesEmptyInput() {
        #expect(PDFPageScanner.pruningEmptyColumns([]).isEmpty)
        #expect(PDFPageScanner.pruningEmptyColumns([[]]) == [[]])
    }

    // MARK: - Rendering

    @Test("A table block renders with a header and delimiter row")
    func rendersTableBlock() {
        let markdown = MarkdownRenderer(options: .default).render(blocks: [
            .table(rows: [["Key", "Status"], ["AB-1", "Open"]])
        ])

        #expect(markdown.contains("| Key | Status |"))
        #expect(markdown.contains("| --- | --- |"))
        #expect(markdown.contains("| AB-1 | Open |"))
    }
}
