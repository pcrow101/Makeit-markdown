import Foundation

/// A failure while reading the parts of a Word document.
enum WordDocumentError: Error, Equatable {
    /// The archive or file is not a Word document.
    case notADocument
    /// A part of the document is not well formed.
    case malformed(part: String)
}

/// Reads a `.docx` Open XML package into document blocks.
enum DOCXReader {

    private static let officeDocumentType =
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"

    /// Reads the blocks of the document in `archive`, saving its pictures in
    /// `images`.
    ///
    /// - Returns: The blocks in reading order, and the number of charts, which
    ///   are not converted.
    static func read(
        _ archive: ZipArchive,
        images: inout WordImageStore
    ) throws -> (blocks: [DocumentBlock], chartCount: Int) {
        let documentPath = try mainDocumentPath(in: archive)
        guard let documentData = try archive.contents(of: documentPath) else {
            throw WordDocumentError.notADocument
        }

        let directory = directoryOf(documentPath)
        let folder = directory.isEmpty ? "" : directory + "/"
        let styles = try parse(archive, at: folder + "styles.xml", with: DOCXStylesParser())?.sheet
        let numbering = try parse(archive, at: folder + "numbering.xml", with: DOCXNumberingParser())?
            .numbering
        let relationshipsPath = folder + "_rels/" + fileName(documentPath) + ".rels"
        let relationships = try relationships(in: archive, at: relationshipsPath)

        let body = DOCXBodyParser()
        try parseXML(documentData, with: body, part: documentPath)

        let assembler = DOCXBodyAssembler(
            styles: styles ?? DOCXStyleSheet(),
            numbering: numbering ?? DOCXNumbering()
        )

        var blocks: [DocumentBlock] = []
        for block in assembler.blocks(from: body.items) {
            guard case .image(let relationshipID, let altText) = block else {
                blocks.append(block)
                continue
            }
            guard images.isEnabled else { continue }
            let target = relationships[relationshipID].map { XLSXWorkbookReader.resolve($0, in: folder) }
            let data = try target.flatMap { try archive.contents(of: $0) }
            if let image = images.block(for: data, key: target ?? relationshipID, altText: altText) {
                blocks.append(image)
            }
        }
        return (blocks, body.chartCount)
    }

    // MARK: - Parts

    /// The path of the main document part, found through the package
    /// relationships.
    private static func mainDocumentPath(in archive: ZipArchive) throws -> String {
        let packageRelationships = try relationshipList(in: archive, at: "_rels/.rels")
        if let main = packageRelationships.first(where: { $0.type == officeDocumentType }) {
            let path = XLSXWorkbookReader.resolve(main.target, in: "")
            if archive.contains(path) { return path }
        }
        guard archive.contains("word/document.xml") else { throw WordDocumentError.notADocument }
        return "word/document.xml"
    }

    private static func parse<Parser: XMLParserDelegate>(
        _ archive: ZipArchive,
        at path: String,
        with parser: Parser
    ) throws -> Parser? {
        guard let data = try archive.contents(of: path) else { return nil }
        try parseXML(data, with: parser, part: path)
        return parser
    }

    private static func relationships(in archive: ZipArchive, at path: String) throws -> [String: String] {
        var targets: [String: String] = [:]
        for relationship in try relationshipList(in: archive, at: path) {
            targets[relationship.identifier] = relationship.target
        }
        return targets
    }

    private static func relationshipList(
        in archive: ZipArchive,
        at path: String
    ) throws -> [XLSXRelationship] {
        try parse(archive, at: path, with: XLSXRelationshipsParser())?.relationships ?? []
    }

    private static func parseXML(_ data: Data, with delegate: XMLParserDelegate, part: String) throws {
        do {
            try XLSXXML.parse(data, with: delegate, part: part)
        } catch {
            throw WordDocumentError.malformed(part: part)
        }
    }

    private static func directoryOf(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    private static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// Turns the paragraphs read by ``DOCXBodyParser`` into document blocks using
/// the document's styles and list definitions.
struct DOCXBodyAssembler {

    let styles: DOCXStyleSheet
    let numbering: DOCXNumbering

    func blocks(from items: [DOCXBodyParser.Item]) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        for item in items {
            switch item {
            case .paragraph(let paragraph):
                if let block = block(for: paragraph) { blocks.append(block) }
                blocks.append(contentsOf: paragraph.images)
            case .table(let rows):
                blocks.append(.table(rows: rows))
            case .image(let image):
                blocks.append(image)
            }
        }
        return blocks
    }

    private func block(for paragraph: DOCXParagraph) -> DocumentBlock? {
        let text = paragraph.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let outline = paragraph.outlineLevel, (0...8).contains(outline) {
            return .heading(text: text, level: outline + 1)
        }

        let role = styles.role(of: paragraph.styleID)
        if case .heading(let level) = role {
            return .heading(text: text, level: level)
        }

        if let list = listNumbering(of: paragraph) {
            return .listItem(
                text: text,
                ordered: numbering.isOrdered(list.id, level: list.level),
                indentLevel: min(max(list.level, 0), 8)
            )
        }

        switch role {
        case .code: return .codeBlock(text: text)
        case .quote: return .blockQuote(text: text)
        case .body, .heading: return paragraph.isMonospace ? .codeBlock(text: text) : .paragraph(text: text)
        }
    }

    /// The list a paragraph belongs to, from its own properties or its style.
    private func listNumbering(of paragraph: DOCXParagraph) -> (id: String, level: Int)? {
        if let identifier = paragraph.numberingID {
            guard numbering.isList(identifier) else { return nil }
            let level = paragraph.numberingLevel ?? styles.numbering(of: paragraph.styleID)?.level ?? 0
            return (identifier, level)
        }
        guard let inherited = styles.numbering(of: paragraph.styleID),
              numbering.isList(inherited.id) else { return nil }
        return (inherited.id, paragraph.numberingLevel ?? inherited.level)
    }
}
