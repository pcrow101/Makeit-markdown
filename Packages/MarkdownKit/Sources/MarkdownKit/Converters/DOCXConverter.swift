import Foundation
import UniformTypeIdentifiers

/// Converts Word documents (`.docx` and `.doc`) into Markdown.
///
/// A file's contents decide how it is read, not its extension, because `.doc`
/// covers several formats in practice:
///
/// - **Open XML packages** (`.docx`) are read directly. Headings come from
///   the paragraph styles, lists from the numbering definitions, and tables
///   and pictures from the document body.
/// - **Word 97–2003 binary files** and **RTF** are read with AppKit's document
///   readers. Headings are inferred from font size and weight.
/// - **Web pages**, which Word saves as HTML or MHTML and Confluence exports
///   with a `.doc` extension, are read from their HTML. Pictures in MHTML
///   files are saved too.
///
/// Inline formatting such as bold, italics and links is not kept. Charts are
/// not converted; a warning counts them.
public struct DOCXConverter: DocumentConverter {

    public let formatName = "Word"

    public var supportedTypes: [UTType] {
        // These identifiers are declared by the system, so they are looked up
        // rather than imported, which would need an Info.plist declaration.
        [
            UTType("org.openxmlformats.wordprocessingml.document"),
            UTType("com.microsoft.word.doc")
        ].compactMap { $0 }
    }

    public init() {}

    public func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        try Task.checkCancellation()

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ConversionError.unreadableDocument(url: url, reason: error.localizedDescription)
        }

        var images = WordImageStore(documentURL: url, isEnabled: options.extractGraphics)
        var warnings: [ConversionWarning] = []
        let blocks = try Self.read(data, url: url, options: options, images: &images, warnings: &warnings)
        warnings.append(contentsOf: images.warnings)

        try Task.checkCancellation()

        let adjusted = WordBlockAdjuster.adjust(blocks, options: options)
        if adjusted.isEmpty && warnings.isEmpty {
            throw ConversionError.noExtractableText(url: url)
        }

        return ConversionResult(
            markdown: MarkdownRenderer(options: options).render(blocks: adjusted),
            sourceURL: url,
            warnings: warnings,
            assets: images.assets
        )
    }

    // MARK: - Formats

    private enum Kind {
        case openXML, compoundFile, rtf, mime, html, unknown

        init(_ data: Data) {
            if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
                self = .openXML
            } else if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
                self = .compoundFile
            } else if data.starts(with: Array("{\\rtf".utf8)) {
                self = .rtf
            } else if MIMEArchive.isMIME(data) {
                self = .mime
            } else if Self.looksLikeHTML(data) {
                self = .html
            } else {
                self = .unknown
            }
        }

        private static func looksLikeHTML(_ data: Data) -> Bool {
            let head = (String(bytes: data.prefix(2048), encoding: .isoLatin1) ?? "").lowercased()
            return head.contains("<html") || head.contains("<!doctype html") || head.contains("<body")
        }
    }

    private static func read(
        _ data: Data,
        url: URL,
        options: ConversionOptions,
        images: inout WordImageStore,
        warnings: inout [ConversionWarning]
    ) throws -> [DocumentBlock] {
        switch Kind(data) {
        case .openXML:
            return try readOpenXML(data, url: url, images: &images, warnings: &warnings)

        case .compoundFile:
            // A .docx in this container is encrypted. A .doc that AppKit
            // cannot open is most often encrypted too.
            guard url.pathExtension.lowercased() != "docx",
                  let text = AttributedDocumentReader.attributedString(from: data, type: .docFormat) else {
                throw ConversionError.passwordProtected(url: url)
            }
            return AttributedDocumentReader.blocks(from: text, options: options, images: &images)

        case .rtf:
            guard let text = AttributedDocumentReader.attributedString(from: data, type: .rtf) else {
                throw ConversionError.unreadableDocument(url: url, reason: "the RTF content is damaged")
            }
            return AttributedDocumentReader.blocks(from: text, options: options, images: &images)

        case .mime:
            guard let archive = MIMEArchive(data: data) else {
                throw ConversionError.unreadableDocument(
                    url: url,
                    reason: "the web archive has no page in it"
                )
            }
            return resolvingImages(in: HTMLBlockReader.blocks(from: archive.html), images: &images) {
                archive.resource(for: $0)
            }

        case .html:
            let html = String(bytes: data, encoding: .utf8)
                ?? String(bytes: data, encoding: .windowsCP1252) ?? ""
            return resolvingImages(in: HTMLBlockReader.blocks(from: html), images: &images) {
                Self.linkedImage($0, beside: url)
            }

        case .unknown:
            throw notAWordDocument(url)
        }
    }

    private static func readOpenXML(
        _ data: Data,
        url: URL,
        images: inout WordImageStore,
        warnings: inout [ConversionWarning]
    ) throws -> [DocumentBlock] {
        do {
            let (blocks, chartCount) = try DOCXReader.read(ZipArchive(data: data), images: &images)
            if chartCount > 0 {
                let charts = chartCount == 1 ? "1 chart" : "\(chartCount) charts"
                warnings.append(ConversionWarning(
                    kind: .unsupportedFeature,
                    message: "The document contains \(charts), which are not converted."
                ))
            }
            return blocks
        } catch let error as ZipArchiveError {
            throw conversionError(for: error, url: url)
        } catch let error as WordDocumentError {
            switch error {
            case .notADocument:
                throw notAWordDocument(url)
            case .malformed(let part):
                throw ConversionError.unreadableDocument(
                    url: url,
                    reason: "\(part) in the document is not valid"
                )
            }
        }
    }

    private static func conversionError(for error: ZipArchiveError, url: URL) -> ConversionError {
        switch error {
        case .encrypted:
            return .passwordProtected(url: url)
        case .notAnArchive:
            return notAWordDocument(url)
        case .entryTooLarge:
            return .unreadableDocument(url: url, reason: "the document is too large to read")
        case .corrupt, .unsupportedCompression, .unsupportedZip64:
            return .unreadableDocument(
                url: url,
                reason: "the document is damaged or uses an unsupported format"
            )
        }
    }

    private static func notAWordDocument(_ url: URL) -> ConversionError {
        .unreadableDocument(url: url, reason: "the file is not a valid Word document")
    }

    // MARK: - Pictures

    /// Replaces the `src` paths of HTML pictures with saved image files.
    private static func resolvingImages(
        in blocks: [DocumentBlock],
        images: inout WordImageStore,
        lookup: (String) -> Data?
    ) -> [DocumentBlock] {
        var resolved: [DocumentBlock] = []
        for block in blocks {
            guard case .image(let source, let altText) = block else {
                resolved.append(block)
                continue
            }
            guard images.isEnabled else { continue }
            let data = inlineImage(source) ?? lookup(source)
            if let image = images.block(for: data, key: source, altText: altText) {
                resolved.append(image)
            }
        }
        return resolved
    }

    /// The bytes of a `data:` URI.
    private static func inlineImage(_ source: String) -> Data? {
        guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[..<comma]
        let payload = String(source[source.index(after: comma)...])
        guard header.hasSuffix(";base64") else {
            return payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    /// A picture an HTML document links to, read from beside the document.
    private static func linkedImage(_ source: String, beside documentURL: URL) -> Data? {
        guard !source.contains("://") else { return nil }
        let path = source.removingPercentEncoding ?? source
        let fileURL = documentURL.deletingLastPathComponent().appending(path: path)
        return try? Data(contentsOf: fileURL)
    }
}
