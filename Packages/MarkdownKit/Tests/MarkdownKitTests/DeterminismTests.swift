import Testing

@testable import MarkdownKit

/// Conversion must give the same answer every time it is run.
///
/// Choosing the most common value from a dictionary is the usual way this
/// breaks, because a dictionary iterates in an order that changes between
/// runs. These tests pin the tie breaks that make the choice repeatable.
@Suite("Determinism")
struct DeterminismTests {

    // MARK: - Font selection

    @Test("The larger face wins when two styles cover the same length")
    func breaksFontTiesBySize() {
        let tally: [PDFConverter.FontStyle: Int] = [
            PDFConverter.FontStyle(pointSize: 12, isBold: false): 40,
            PDFConverter.FontStyle(pointSize: 18, isBold: false): 40
        ]

        #expect(PDFConverter.dominantStyle(from: tally).pointSize == 18)
    }

    @Test("The bolder face wins when size and length both match")
    func breaksFontTiesByWeight() {
        let tally: [PDFConverter.FontStyle: Int] = [
            PDFConverter.FontStyle(pointSize: 14, isBold: false): 25,
            PDFConverter.FontStyle(pointSize: 14, isBold: true): 25
        ]

        #expect(PDFConverter.dominantStyle(from: tally).isBold)
    }

    @Test("Coverage still decides when it differs")
    func prefersTheWidestCoverage() {
        let tally: [PDFConverter.FontStyle: Int] = [
            PDFConverter.FontStyle(pointSize: 24, isBold: true): 3,
            PDFConverter.FontStyle(pointSize: 11, isBold: false): 90
        ]

        #expect(PDFConverter.dominantStyle(from: tally).pointSize == 11)
    }

    @Test("Repeating the choice gives the same answer")
    func repeatsTheSameChoice() {
        // Built fresh each time so the dictionary is seeded anew.
        let results = (0..<50).map { _ -> PDFConverter.FontStyle in
            let tally: [PDFConverter.FontStyle: Int] = [
                PDFConverter.FontStyle(pointSize: 10, isBold: false): 12,
                PDFConverter.FontStyle(pointSize: 13, isBold: true): 12,
                PDFConverter.FontStyle(pointSize: 13, isBold: false): 12,
                PDFConverter.FontStyle(pointSize: 9, isBold: true): 12
            ]
            return PDFConverter.dominantStyle(from: tally)
        }

        #expect(Set(results).count == 1)
        #expect(results[0] == PDFConverter.FontStyle(pointSize: 13, isBold: true))
    }

    @Test("An empty tally falls back to body text")
    func fallsBackWhenNothingIsTallied() {
        let style = PDFConverter.dominantStyle(from: [:])

        #expect(style.pointSize == 12)
        #expect(!style.isBold)
    }

    // MARK: - Whole document

    @Test("Converting the same document twice gives the same Markdown")
    func convertsRepeatably() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            pages: [
                [
                    PDFFixture.Line("A Title", fontSize: 20, isBold: true),
                    PDFFixture.Line("Body text of the first page."),
                    PDFFixture.Line("• A point"),
                    PDFFixture.Line("• Another point")
                ],
                [
                    PDFFixture.Line("Second Page", fontSize: 16, isBold: true),
                    PDFFixture.Line("More body text follows here.")
                ]
            ],
            named: "repeatable",
            in: scratch.directory
        )

        let converter = PDFConverter()
        var outputs: Set<String> = []
        for _ in 0..<5 {
            outputs.insert(try await converter.convert(url: url, options: .default).markdown)
        }

        #expect(outputs.count == 1)
    }

    @Test("Table extraction is repeatable too")
    func extractsTablesRepeatably() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            tableRows: [
                ["Key", "Summary", "Status"],
                ["AB-1", "First issue", "Open"],
                ["AB-2", "Second issue", "Closed"]
            ],
            named: "repeatable-table",
            in: scratch.directory
        )

        let converter = PDFConverter()
        let options = ConversionOptions(extractTables: true)
        var outputs: Set<String> = []
        for _ in 0..<5 {
            outputs.insert(try await converter.convert(url: url, options: options).markdown)
        }

        #expect(outputs.count == 1)
    }
}
