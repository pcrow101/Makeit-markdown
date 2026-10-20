import Foundation
import Testing
@testable import MarkdownKit

@Suite("PDFConverter")
struct PDFConverterTests {

    private let converter = PDFConverter()

    @Test("Plain prose converts to paragraph text")
    func plainParagraphs() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [
                PDFFixture.Line("The quick brown fox jumps over the lazy dog."),
                PDFFixture.Line("A second sentence follows the first.")
            ],
            named: "prose",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.markdown.contains("The quick brown fox jumps over the lazy dog."))
        #expect(result.markdown.contains("A second sentence follows the first."))
        #expect(result.pageCount == 1)
        #expect(result.sourceURL == url)
    }

    @Test("A larger opening line becomes a heading")
    func headingDetection() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [
                PDFFixture.Line("Annual Report", fontSize: 28, isBold: true),
                PDFFixture.Line("This paragraph establishes the body text size.", fontSize: 11),
                PDFFixture.Line("A further line of body text reinforces the size.", fontSize: 11)
            ],
            named: "heading",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.markdown.hasPrefix("# Annual Report"))
    }

    @Test("Bulleted lines become a Markdown list")
    func listDetection() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [
                PDFFixture.Line("• First point"),
                PDFFixture.Line("• Second point")
            ],
            named: "list",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.markdown.contains("- First point"))
        #expect(result.markdown.contains("- Second point"))
    }

    @Test("Page breaks are inserted between pages when requested")
    func pageBreaks() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            pages: [
                [PDFFixture.Line("Content on the first page.")],
                [PDFFixture.Line("Content on the second page.")]
            ],
            named: "paged",
            in: scratch.directory
        )

        let result = try await converter.convert(
            url: url,
            options: ConversionOptions(insertPageBreaks: true)
        )

        #expect(result.pageCount == 2)
        #expect(result.markdown.contains("\n---\n"))
    }

    @Test("A document with no text is reported rather than returned empty")
    func emptyDocument() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.writeBlank(named: "blank", in: scratch.directory)

        await #expect(throws: ConversionError.noExtractableText(url: url)) {
            try await converter.convert(url: url, options: .default)
        }
    }

    @Test("A file that is not a PDF is reported as unreadable")
    func unreadableDocument() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "broken.pdf")
        try "this is not a PDF".write(to: url, atomically: true, encoding: .utf8)

        await #expect(throws: ConversionError.self) {
            try await converter.convert(url: url, options: .default)
        }
    }

    @Test("Table extraction is on by default and raises no warning")
    func tableExtractionRaisesNoWarning() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [PDFFixture.Line("Some ordinary content.")],
            named: "tables",
            in: scratch.directory
        )

        #expect(ConversionOptions.default.extractTables)

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.warnings.isEmpty)
    }

    @Test("A page without text raises an empty page warning")
    func emptyPageWarning() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            pages: [
                [PDFFixture.Line("The first page has content.")],
                []
            ],
            named: "mixed",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.warnings.contains { $0.kind == .emptyPage })
    }

    @Test("The suggested file name replaces the source extension")
    func suggestedFileName() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            lines: [PDFFixture.Line("Content.")],
            named: "quarterly.results",
            in: scratch.directory
        )

        let result = try await converter.convert(url: url, options: .default)

        #expect(result.suggestedFileName == "quarterly.results.md")
    }

    @Test("Conversion honours task cancellation")
    func cancellation() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = try PDFFixture.write(
            pages: Array(repeating: [PDFFixture.Line("Page content.")], count: 50),
            named: "long",
            in: scratch.directory
        )

        let task = Task {
            try await converter.convert(url: url, options: .default)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("The converter claims only PDF documents")
    func supportedTypes() {
        #expect(converter.supportedFileExtensions.contains("pdf"))
        #expect(converter.accepts(.pdf))
        #expect(!converter.accepts(.png))
    }
}
