import Foundation
import Testing
@testable import MarkdownKit

@Suite("Word (.docx) conversion")
struct DOCXConverterTests {

    private typealias Fixture = DOCXFixture

    private func convert(
        _ body: String,
        image: Data? = nil,
        options: ConversionOptions = .default
    ) async throws -> ConversionResult {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "Report.docx")
        try Fixture.write(body: body, image: image, to: url)
        return try await DOCXConverter().convert(url: url, options: options)
    }

    @Test("Heading styles, including inherited ones, become Markdown headings")
    func headings() async throws {
        let result = try await convert(
            Fixture.paragraph("Report", style: "Title")
                + Fixture.paragraph("Overview", style: "Heading1")
                + Fixture.paragraph("Details", style: "Heading2")
                + Fixture.paragraph("Custom", style: "MySection")
                + Fixture.paragraph("Body text.")
        )
        #expect(result.markdown == "# Report\n\n# Overview\n\n## Details\n\n## Custom\n\nBody text.\n")
    }

    @Test("Numbering definitions decide bullets, numbers and nesting")
    func lists() async throws {
        let result = try await convert(
            Fixture.paragraph("Apples", list: (1, 0))
                + Fixture.paragraph("Step one", list: (1, 1))
                + Fixture.paragraph("Pears", list: (1, 0))
                + Fixture.paragraph("Then")
                + Fixture.paragraph("First", list: (2, 0))
                + Fixture.paragraph("Second", list: (2, 0))
        )
        #expect(result.markdown.contains("- Apples\n\n  1. Step one\n\n- Pears"))
        #expect(result.markdown.contains("1. First\n2. Second"))
    }

    @Test("Numbering ID 0 removes a list")
    func numberingRemoved() async throws {
        let result = try await convert(Fixture.paragraph("Plain", list: (0, 0)))
        #expect(result.markdown == "Plain\n")
    }

    @Test("Tables keep their first row as the header and pad spanned cells")
    func tables() async throws {
        let result = try await convert(Fixture.table([
            [Fixture.textCell("Name"), Fixture.textCell("Value"), Fixture.textCell("Notes")],
            [Fixture.textCell("Wide", span: 2), Fixture.textCell("a | b")],
            [Fixture.cell(Fixture.paragraph("Two"), Fixture.paragraph("lines")), Fixture.textCell("2"),
             Fixture.textCell("")]
        ]))
        #expect(result.markdown == """
            | Name | Value | Notes |
            | --- | --- | --- |
            | Wide |  | a \\| b |
            | Two lines | 2 |  |

            """)
    }

    @Test("A single-cell table holding code becomes a code block")
    func boxedCode() async throws {
        let result = try await convert(Fixture.table([[
            Fixture.cell(Fixture.codeParagraph("let x = 1"), Fixture.codeParagraph("print(x)"))
        ]]))
        #expect(result.markdown == "```\nlet x = 1\nprint(x)\n```\n")
    }

    @Test("Code and quote styles become fenced code and block quotes")
    func codeAndQuoteStyles() async throws {
        let result = try await convert(
            Fixture.paragraph("make build", style: "SourceCode")
                + Fixture.paragraph("make test", style: "SourceCode")
                + Fixture.paragraph("Well said.", style: "Quote")
        )
        #expect(result.markdown == "```\nmake build\nmake test\n```\n\n> Well said.\n")
    }

    @Test("Deleted text, field codes and fallback content are left out")
    func hiddenContent() async throws {
        let body = """
            <w:p><w:r><w:t>Kept </w:t></w:r><w:del><w:r><w:delText>gone </w:delText></w:r></w:del>\
            <w:r><w:instrText> PAGE </w:instrText></w:r><w:r><w:t>text</w:t></w:r>\
            <mc:AlternateContent><mc:Choice Requires="wps"><w:r><w:t> once</w:t></w:r></mc:Choice>\
            <mc:Fallback><w:r><w:t> twice</w:t></w:r></mc:Fallback></mc:AlternateContent></w:p>
            """
        let result = try await convert(body)
        #expect(result.markdown == "Kept text once\n")
    }

    @Test("Pictures are saved beside the Markdown and referenced from it")
    func pictures() async throws {
        let png = Fixture.pngImage()
        let result = try await convert(Fixture.picture(description: "System diagram"), image: png)

        #expect(result.markdown == "![System diagram](Report_images/image-1.png)\n")
        #expect(result.assets == [ConversionAsset(relativePath: "Report_images/image-1.png", data: png)])
    }

    @Test("Pictures are skipped when graphics extraction is off")
    func picturesDisabled() async throws {
        var options = ConversionOptions.default
        options.extractGraphics = false
        let result = try await convert(
            Fixture.paragraph("Text") + Fixture.picture(description: "Diagram"),
            image: Fixture.pngImage(),
            options: options
        )
        #expect(result.markdown == "Text\n")
        #expect(result.assets.isEmpty)
    }

    @Test("A picture in an unsupported format produces a warning")
    func unsupportedPicture() async throws {
        let result = try await convert(
            Fixture.paragraph("Text") + Fixture.picture(description: "Old drawing"),
            image: Data("not an image".utf8)
        )
        #expect(result.assets.isEmpty)
        #expect(result.warnings.contains {
            $0.kind == .unsupportedFeature && $0.message.contains("1 picture")
        })
    }

    @Test("Charts produce a warning")
    func charts() async throws {
        let body = Fixture.paragraph("Sales")
            + "<w:p><w:r><w:drawing><a:graphic><a:graphicData><c:chart r:id=\"rId5\"/>"
            + "</a:graphicData></a:graphic></w:drawing></w:r></w:p>"
        let result = try await convert(body)
        #expect(result.warnings.contains { $0.message.contains("1 chart") })
    }

    @Test("Turning options off writes headings, lists and tables as paragraphs")
    func optionsOff() async throws {
        let options = ConversionOptions(detectHeadings: false, detectLists: false, extractTables: false)
        let result = try await convert(
            Fixture.paragraph("Title", style: "Heading1")
                + Fixture.paragraph("Item", list: (1, 0))
                + Fixture.table([[Fixture.textCell("A"), Fixture.textCell("B")]]),
            options: options
        )
        #expect(result.markdown == "Title\n\nItem\n\nA B\n")
    }

    @Test("A document without text is reported")
    func emptyDocument() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "Empty.docx")
        try Fixture.write(body: Fixture.paragraph("  "), to: url)

        await #expect(throws: ConversionError.noExtractableText(url: url)) {
            try await DOCXConverter().convert(url: url, options: .default)
        }
    }

    @Test("An encrypted .docx is reported as password protected")
    func encrypted() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "Secret.docx")
        let header: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        try Data(header + Array(repeating: 0, count: 504)).write(to: url)

        await #expect(throws: ConversionError.passwordProtected(url: url)) {
            try await DOCXConverter().convert(url: url, options: .default)
        }
    }

    @Test("A ZIP archive that is not a Word document is reported as unreadable")
    func notADocument() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "Other.docx")
        try XLSXFixture.zip([("readme.txt", Data("hello".utf8))]).write(to: url)

        await #expect(throws: ConversionError.unreadableDocument(
            url: url,
            reason: "the file is not a valid Word document"
        )) {
            try await DOCXConverter().convert(url: url, options: .default)
        }
    }
}
