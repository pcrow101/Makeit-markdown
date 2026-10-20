import AppKit
import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Converts PDF documents into Markdown using PDFKit.
///
/// Emits headings, lists, tables and plain paragraph text, and can save
/// pictures, drawings and charts as images. Tables are recovered from page
/// geometry and can be turned off with ``ConversionOptions/extractTables``.
/// Scanned documents are reported as warnings rather than being passed
/// through optical character recognition, which is out of scope.
public struct PDFConverter: DocumentConverter {

    public let formatName = "PDF"

    public var supportedTypes: [UTType] { [.pdf] }

    public init() {}

    public func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.unreadableDocument(
                url: url,
                reason: "the file is not a valid PDF document"
            )
        }

        if document.isEncrypted && document.isLocked {
            throw ConversionError.passwordProtected(url: url)
        }

        var warnings = Self.openingWarnings(for: document)

        let analyzer = DocumentStructureAnalyzer(options: options)
        var pageElements: [[PDFPageScanner.Element]] = []
        var emptyPageNumbers: [Int] = []
        var pageFigures: [[Figure]] = []
        var assets: [ConversionAsset] = []
        var continuation: RuledTableContinuation?

        let stem = url.deletingPathExtension().lastPathComponent
        let assetFolder = "\(stem)_images"

        for index in 0..<document.pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: index) else { continue }

            let elements = Self.elements(on: page, options: options, continuation: &continuation)

            let figures = options.extractGraphics
                ? Self.figures(on: page, pageNumber: index + 1, folder: assetFolder, assets: &assets)
                : []

            if elements.isEmpty && figures.isEmpty {
                emptyPageNumbers.append(index + 1)
            }
            pageElements.append(elements)
            pageFigures.append(figures)
        }

        // Running headers and footers are only detectable once every page has
        // been read, so stripping happens after extraction and before analysis.
        if options.stripRepeatedPageFurniture {
            pageElements = Self.stripPageFurniture(from: pageElements)
        }

        let pages = zip(pageElements, pageFigures).map {
            Self.blocks(for: $0, figures: $1, analyzer: analyzer)
        }

        if !emptyPageNumbers.isEmpty {
            warnings.append(Self.emptyPageWarning(for: emptyPageNumbers, pageCount: document.pageCount))
        }

        let markdown = MarkdownRenderer(options: options).render(pages: pages)

        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noExtractableText(url: url)
        }

        return ConversionResult(
            markdown: markdown,
            sourceURL: url,
            pageCount: document.pageCount,
            warnings: warnings,
            assets: assets
        )
    }

    /// A graphic placed on a page, positioned by its top edge.
    private struct Figure {
        var top: Double
        var block: DocumentBlock
    }

    /// Reads the text and tables of `page`.
    ///
    /// Scanning recovers page geometry, which is what makes tables
    /// recoverable. With table extraction off, text is read in document order
    /// and no table is built.
    private static func elements(
        on page: PDFPage,
        options: ConversionOptions,
        continuation: inout RuledTableContinuation?
    ) -> [PDFPageScanner.Element] {
        guard options.extractTables else {
            return textLines(in: page).map { .line($0) }
        }

        let ownGrids = PDFRuledTable.grids(on: page)
        let grids = ownGrids.isEmpty ? (continuation.map { [$0.grid] } ?? []) : ownGrids

        var elements = PDFPageScanner.scan(
            page: page,
            grids: grids,
            detectAlignedTables: true
        )
        if ownGrids.isEmpty, let continuation {
            elements = continuation.completing(elements)
        }

        continuation = RuledTableContinuation.after(
            elements: elements,
            ownGrid: ownGrids.last,
            previous: continuation,
            pageRect: page.bounds(for: .cropBox)
        )
        return elements
    }

    private static func openingWarnings(for document: PDFDocument) -> [ConversionWarning] {
        var warnings: [ConversionWarning] = []

        if document.isEncrypted {
            warnings.append(
                ConversionWarning(
                    kind: .encryptedDocument,
                    message: "The document is encrypted but was opened without a password."
                )
            )
        }
        return warnings
    }

    /// Renders the graphics on `page`, appending their files to `assets`.
    private static func figures(
        on page: PDFPage,
        pageNumber: Int,
        folder: String,
        assets: inout [ConversionAsset]
    ) -> [Figure] {
        let encodedFolder = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder
        var figures: [Figure] = []

        for (offset, region) in PDFGraphicsExtractor.regions(on: page).enumerated() {
            guard let data = PDFGraphicsExtractor.renderPNG(of: region, on: page) else { continue }
            let name = "page-\(pageNumber)-figure-\(offset + 1).png"
            assets.append(ConversionAsset(relativePath: "\(folder)/\(name)", data: data))
            figures.append(
                Figure(
                    top: Double(region.rect.maxY),
                    block: .image(
                        path: "\(encodedFolder)/\(name)",
                        altText: "Figure \(offset + 1) (page \(pageNumber))"
                    )
                )
            )
        }
        return figures
    }

    // MARK: - Page assembly

    /// Converts scanned elements into structural blocks.
    ///
    /// Runs of ordinary lines are handed to the structural analyser together so
    /// that paragraphs, headings and lists are recovered exactly as they are on
    /// a page with no tables.
    private static func blocks(
        for elements: [PDFPageScanner.Element],
        figures: [Figure],
        analyzer: DocumentStructureAnalyzer
    ) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        var pending: [TextLine] = []
        let pageLines = elements.compactMap { element -> TextLine? in
            if case .line(let line) = element { return line }
            return nil
        }
        let bodyFontSize = pageLines.isEmpty ? nil : DocumentStructureAnalyzer.modalFontSize(of: pageLines)
        var remainingFigures = figures.sorted { $0.top > $1.top }[...]

        func flush() {
            guard !pending.isEmpty else { return }
            blocks.append(contentsOf: analyzer.analyze(lines: pending, bodyFontSize: bodyFontSize))
            pending.removeAll(keepingCapacity: true)
        }

        for element in elements {
            switch element {
            case .line(let line):
                // Figures are placed before the first line that sits below
                // their top edge, which keeps them in reading order.
                if let top = line.top {
                    while let figure = remainingFigures.first, figure.top >= top {
                        flush()
                        blocks.append(figure.block)
                        remainingFigures = remainingFigures.dropFirst()
                    }
                }
                pending.append(line)
            case .table(let rows):
                flush()
                blocks.append(.table(rows: rows))
            }
        }

        flush()
        blocks.append(contentsOf: remainingFigures.map(\.block))
        return blocks
    }

    /// Removes repeated running headers and footers from scanned pages.
    ///
    /// The filter works on plain lines, so the lines are projected out, filtered
    /// and then matched back against the original elements. The filter only ever
    /// removes lines and preserves their order, which makes a single forward
    /// pass enough to decide what to keep.
    private static func stripPageFurniture(
        from pages: [[PDFPageScanner.Element]]
    ) -> [[PDFPageScanner.Element]] {
        let projected = pages.map { page in
            page.compactMap { element -> TextLine? in
                if case .line(let line) = element { return line }
                return nil
            }
        }

        let kept = PageFurnitureFilter.strip(pages: projected)

        return zip(pages, kept).map { page, keptLines in
            var remaining = keptLines[...]
            return page.filter { element in
                guard case .line(let line) = element else { return true }
                guard remaining.first == line else { return false }
                remaining = remaining.dropFirst()
                return true
            }
        }
    }

    // MARK: - Text extraction

    /// Extracts positioned, styled lines from a single page.
    ///
    /// PDFKit exposes styling through the page's attributed string, so glyph
    /// runs are walked to recover the dominant font of each visual line.
    static func textLines(in page: PDFPage) -> [TextLine] {
        guard let attributed = page.attributedString, attributed.length > 0 else { return [] }

        let fullText = attributed.string
        var lines: [TextLine] = []

        fullText.enumerateSubstrings(
            in: fullText.startIndex..<fullText.endIndex,
            options: [.byLines]
        ) { substring, range, _, _ in
            guard let substring, !substring.trimmingCharacters(in: .whitespaces).isEmpty else { return }

            let nsRange = NSRange(range, in: fullText)
            let style = Self.dominantStyle(in: attributed, range: nsRange)
            let bounds = Self.firstGlyphBounds(of: nsRange, on: page)

            lines.append(
                TextLine(
                    text: Self.sanitize(substring),
                    fontSize: style.pointSize,
                    isBold: style.isBold,
                    indent: bounds.map { Double($0.minX) } ?? 0,
                    top: bounds.map { Double($0.maxY) }
                )
            )
        }

        return lines
    }

    struct FontStyle: Hashable {
        var pointSize: Double
        var isBold: Bool
    }

    /// The font style covering the greatest number of characters in `range`.
    private static func dominantStyle(in attributed: NSAttributedString, range: NSRange) -> FontStyle {
        var tally: [FontStyle: Int] = [:]

        attributed.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let style = FontStyle(
                pointSize: Double(font.pointSize),
                isBold: font.fontDescriptor.symbolicTraits.contains(.bold)
            )
            tally[style, default: 0] += subrange.length
        }

        return dominantStyle(from: tally)
    }

    /// The most used style in `tally`, chosen the same way every time.
    ///
    /// A dictionary iterates in an order that changes between runs, so taking
    /// the largest count alone would pick an arbitrary winner whenever two
    /// styles cover the same number of characters, and the same document would
    /// convert differently from one run to the next. Ties therefore fall back
    /// to the larger point size, and then to the bolder face.
    static func dominantStyle(from tally: [FontStyle: Int]) -> FontStyle {
        tally.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            if lhs.key.pointSize != rhs.key.pointSize { return lhs.key.pointSize < rhs.key.pointSize }
            return !lhs.key.isBold && rhs.key.isBold
        }?.key ?? FontStyle(pointSize: 12, isBold: false)
    }

    /// The bounds of the first glyph of `range` on the page.
    private static func firstGlyphBounds(of range: NSRange, on page: PDFPage) -> CGRect? {
        guard range.length > 0,
              let selection = page.selection(for: NSRange(location: range.location, length: 1)) else {
            return nil
        }
        let bounds = selection.bounds(for: page)
        return bounds.isNull || bounds.isInfinite ? nil : bounds
    }

    /// Removes artefacts that commonly survive PDF text extraction.
    private static func sanitize(_ line: String) -> String {
        line
            // Soft hyphens and zero width characters add noise for tokenisers.
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            // Non-breaking spaces behave unpredictably in Markdown.
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func emptyPageWarning(for pageNumbers: [Int], pageCount: Int) -> ConversionWarning {
        let allPagesEmpty = pageNumbers.count == pageCount
        let kind: ConversionWarning.Kind = allPagesEmpty ? .imageOnlyContent : .emptyPage

        let listed = pageNumbers.prefix(10).map(String.init).joined(separator: ", ")
        let suffix = pageNumbers.count > 10 ? ", and \(pageNumbers.count - 10) more" : ""

        let message = allPagesEmpty
            ? "No page contained extractable text. The document is probably scanned images; "
                + "Makeit-Markdown does not perform text recognition."
            : "No text was found on page\(pageNumbers.count == 1 ? "" : "s") \(listed)\(suffix)."

        return ConversionWarning(kind: kind, message: message)
    }
}
