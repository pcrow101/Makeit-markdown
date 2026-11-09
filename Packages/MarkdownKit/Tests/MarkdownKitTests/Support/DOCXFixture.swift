import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds Word documents for tests, so no binary fixtures are committed.
enum DOCXFixture {

    private static let main = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let package = "http://schemas.openxmlformats.org/package/2006/relationships"

    /// A paragraph with an optional style, list numbering and direct text.
    static func paragraph(
        _ text: String,
        style: String? = nil,
        list: (id: Int, level: Int)? = nil
    ) -> String {
        var properties = ""
        if let style { properties += "<w:pStyle w:val=\"\(style)\"/>" }
        if let list {
            properties += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/>"
                + "<w:numId w:val=\"\(list.id)\"/></w:numPr>"
        }
        let pPr = properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
        return "<w:p>\(pPr)<w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    /// A paragraph set in a fixed-width font.
    static func codeParagraph(_ text: String) -> String {
        "<w:p><w:r><w:rPr><w:rFonts w:ascii=\"Consolas\" w:hAnsi=\"Consolas\"/></w:rPr>"
            + "<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    /// A table whose cells are given as raw cell XML, so spans can be tested.
    static func table(_ rows: [[String]]) -> String {
        let body = rows.map { row in
            "<w:tr>" + row.joined() + "</w:tr>"
        }.joined()
        return "<w:tbl><w:tblPr/>\(body)</w:tbl>"
    }

    /// A table cell holding `paragraphs`, spanning `span` grid columns.
    static func cell(_ paragraphs: String..., span: Int = 1) -> String {
        let properties = span > 1 ? "<w:tcPr><w:gridSpan w:val=\"\(span)\"/></w:tcPr>" : ""
        return "<w:tc>\(properties)\(paragraphs.joined())</w:tc>"
    }

    /// A cell holding one plain paragraph.
    static func textCell(_ text: String, span: Int = 1) -> String {
        cell(paragraph(text), span: span)
    }

    /// A paragraph showing the picture with relationship `rId9`.
    static func picture(description: String) -> String {
        """
        <w:p><w:r><w:drawing><wp:inline><wp:docPr id="1" name="Picture 1" descr="\(escape(description))"/>\
        <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rId9"/></pic:blipFill>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    /// Writes a `.docx` whose body is `body` to `url`.
    ///
    /// - Parameter image: The bytes of the picture `rId9` refers to.
    static func write(body: String, image: Data? = nil, to url: URL) throws {
        var parts: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(packageRelationships.utf8)),
            ("word/document.xml", Data(document(body).utf8)),
            ("word/styles.xml", Data(styles.utf8)),
            ("word/numbering.xml", Data(numbering.utf8)),
            ("word/_rels/document.xml.rels", Data(documentRelationships.utf8))
        ]
        if let image {
            parts.append(("word/media/image1.png", image))
        }
        try XLSXFixture.zip(parts, deflate: true).write(to: url)
    }

    /// A one pixel PNG image.
    static func pngImage() -> Data {
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 2, height: 2))

        let output = NSMutableData()
        guard let image = context?.makeImage(),
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    // MARK: - Parts

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func document(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(main)" xmlns:r="\(relationships)" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" \
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" \
        xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">\
        <w:body>\(body)</w:body></w:document>
        """
    }

    private static let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="xml" ContentType="application/xml"/></Types>
        """

    private static let packageRelationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="\(package)">\
        <Relationship Id="rId1" Type="\(relationships)/officeDocument" Target="word/document.xml"/>\
        </Relationships>
        """

    private static let documentRelationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="\(package)">\
        <Relationship Id="rId1" Type="\(relationships)/styles" Target="styles.xml"/>\
        <Relationship Id="rId9" Type="\(relationships)/image" Target="media/image1.png"/>\
        </Relationships>
        """

    /// Heading styles, a code style, and a custom style based on Heading 2.
    private static let styles = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:styles xmlns:w="\(main)">\
        <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>\
        <w:pPr><w:outlineLvl w:val="0"/></w:pPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>\
        <w:style w:type="paragraph" w:styleId="MySection"><w:name w:val="My Section"/>\
        <w:basedOn w:val="Heading2"/></w:style>\
        <w:style w:type="paragraph" w:styleId="SourceCode"><w:name w:val="Source Code"/></w:style>\
        <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/></w:style>\
        </w:styles>
        """

    /// List 1 is bulleted at level 0 and numbered at level 1; list 2 is numbered.
    private static let numbering = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:numbering xmlns:w="\(main)">\
        <w:abstractNum w:abstractNumId="10"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl>\
        <w:lvl w:ilvl="1"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>\
        <w:abstractNum w:abstractNumId="20">\
        <w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>\
        <w:num w:numId="1"><w:abstractNumId w:val="10"/></w:num>\
        <w:num w:numId="2"><w:abstractNumId w:val="20"/></w:num>\
        </w:numbering>
        """
}
