import AppKit
import Foundation
import Testing
@testable import MarkdownKit

@Suite("Word (.doc) conversion")
struct WordLegacyConverterTests {

    private func convert(_ data: Data, name: String = "Page.doc") async throws -> ConversionResult {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: name)
        try data.write(to: url)
        return try await DOCXConverter().convert(url: url, options: .default)
    }

    // MARK: - HTML

    @Test("HTML saved as .doc keeps headings, lists, code and tables")
    func html() async throws {
        let html = """
            <html><head><title>Ignored</title><style>p { color: red; }</style></head><body>
            <h1>Guide</h1>
            <p>Fish &amp; chips&nbsp;cost &#163;5.</p>
            <ul><li>One<ul><li>Nested</li></ul></li><li>Two</li></ul>
            <ol><li>First<li>Second</ol>
            <pre>line 1
              line 2</pre>
            <table><tr><th>Key</th><th>Value</th></tr><tr><td colspan="2">Both</td></tr></table>
            <!-- a comment --><blockquote>Quoted</blockquote>
            </body></html>
            """
        let result = try await convert(Data(html.utf8))
        #expect(result.markdown == """
            # Guide

            Fish & chips cost £5.

            - One

              - Nested

            - Two

            1. First
            2. Second

            ```
            line 1
              line 2
            ```

            | Key | Value |
            | --- | --- |
            | Both |  |

            > Quoted

            """)
    }

    @Test("A '>' inside a quoted attribute does not end the tag")
    func quotedAttribute() {
        let tokens = HTMLTokenizer.tokens(in: "<h2 id=\"a>b\">Title</h2>")
        #expect(tokens == [.start(name: "h2", attributes: ["id": "a>b"]), .text("Title"), .end(name: "h2")])
    }

    @Test("Inline data URI pictures are saved")
    func dataURIPicture() async throws {
        let png = DOCXFixture.pngImage()
        let html = "<html><body><p>Before</p><img src=\"data:image/png;base64,\(png.base64EncodedString())\" "
            + "alt=\"Logo\"></body></html>"
        let result = try await convert(Data(html.utf8))
        #expect(result.markdown == "Before\n\n![Logo](Page_images/image-1.png)\n")
        #expect(result.assets.first?.data == png)
    }

    // MARK: - MHTML

    @Test("A MIME web archive saved as .doc is read with its pictures")
    func mimeArchive() async throws {
        let png = DOCXFixture.pngImage()
        let message = """
            Subject: Exported From Confluence\r
            MIME-Version: 1.0\r
            Content-Type: multipart/related;\r
             boundary="----=_Part_1"\r
            \r
            ------=_Part_1\r
            Content-Type: text/html; charset=UTF-8\r
            Content-Transfer-Encoding: quoted-printable\r
            Content-Location: file:///C:/exported.html\r
            \r
            <html><body><h2 id=3D"x">Caf=C3=A9 notes</h2><p>A long line that is =\r
            wrapped.</p><img src=3D"file:///C:/abc123"></body></html>\r
            ------=_Part_1\r
            Content-Type: application/octet-stream\r
            Content-Transfer-Encoding: base64\r
            Content-Location: file:///C:/abc123\r
            \r
            \(png.base64EncodedString(options: .lineLength76Characters))\r
            ------=_Part_1--\r

            """
        let result = try await convert(Data(message.utf8), name: "Export.doc")
        #expect(result.markdown == "## Café notes\n\nA long line that is wrapped.\n\n"
            + "![Image 1](Export_images/image-1.png)\n")
        #expect(result.assets.first?.data == png)
    }

    // MARK: - Styled text

    @Test("RTF saved as .doc infers headings from font size")
    func rtf() async throws {
        let data = try styledDocument(type: .rtf)
        #expect(data.starts(with: Array("{\\rtf".utf8)))
        let result = try await convert(data)
        #expect(result.markdown.hasPrefix("# Project Plan\n\nThe plan has two phases"))
    }

    @Test("A Word 97–2003 binary document is read")
    func binaryWord() async throws {
        let data = try styledDocument(type: .docFormat)
        #expect(data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]))
        let result = try await convert(data)
        #expect(result.markdown.contains("Project Plan"))
        #expect(result.markdown.contains("The plan has two phases"))
    }

    @Test("A file that is no known Word format is reported as unreadable")
    func unknownFormat() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "Notes.doc")
        try Data("just some text".utf8).write(to: url)

        await #expect(throws: ConversionError.unreadableDocument(
            url: url,
            reason: "the file is not a valid Word document"
        )) {
            try await DOCXConverter().convert(url: url, options: .default)
        }
    }

    /// A heading in a large font followed by body text, saved as `type`.
    private func styledDocument(type: NSAttributedString.DocumentType) throws -> Data {
        let text = NSMutableAttributedString(
            string: "Project Plan\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]
        )
        let body = "The plan has two phases. The first phase gathers requirements. "
            + "The second phase builds and ships the product.\n"
        text.append(NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        return try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: type]
        )
    }
}
