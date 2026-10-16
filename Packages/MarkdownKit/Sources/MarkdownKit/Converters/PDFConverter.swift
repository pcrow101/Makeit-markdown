import AppKit
import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Converts PDF documents into Markdown using PDFKit.
///
/// Version one emits headings, lists and plain paragraph text. Table
/// reconstruction is gated behind
/// ``ConversionOptions/experimentalTableExtraction`` because recovering tabular
/// structure from positioned glyphs is unreliable. Scanned documents are
/// reported as warnings rather than being passed through optical character
/// recognition, which is out of scope.
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

        var warnings: [ConversionWarning] = []

        if document.isEncrypted {
            warnings.append(
                ConversionWarning(
                    kind: .encryptedDocument,
                    message: "The document is encrypted but was opened without a password."
                )
            )
        }

        if options.experimentalTableExtraction {
            warnings.append(
                ConversionWarning(
                    kind: .experimentalTableHeuristic,
                    message: "Experimental table extraction is enabled. Verify tables against the source."
                )
            )
        }

        let analyzer = DocumentStructureAnalyzer(options: options)
        var pageElements: [[PDFPageScanner.Element]] = []
        var emptyPageNumbers: [Int] = []

        for index in 0..<document.pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: index) else { continue }

            // Scanning recovers page geometry, which is what makes tables
            // recoverable. It is only used when tables are requested, so that
            // ordinary conversions keep their established behaviour.
            let elements: [PDFPageScanner.Element] = options.experimentalTableExtraction
                ? PDFPageScanner.scan(page: page)
                : Self.textLines(in: page).map { .line($0) }

            if elements.isEmpty {
                emptyPageNumbers.append(index + 1)
            }
            pageElements.append(elements)
        }

        // Running headers and footers are only detectable once every page has
        // been read, so stripping happens after extraction and before analysis.
        if options.stripRepeatedPageFurniture {
            pageElements = Self.stripPageFurniture(from: pageElements)
        }

        let pages = pageElements.map { Self.blocks(for: $0, analyzer: analyzer) }

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
            warnings: warnings
        )
    }

    // MARK: - Page assembly

    /// Converts scanned elements into structural blocks.
    ///
    /// Runs of ordinary lines are handed to the structural analyser together so
    /// that paragraphs, headings and lists are recovered exactly as they are on
    /// a page with no tables.
    private static func blocks(
        for elements: [PDFPageScanner.Element],
        analyzer: DocumentStructureAnalyzer
    ) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        var pending: [TextLine] = []

        func flush() {
            guard !pending.isEmpty else { return }
            blocks.append(contentsOf: analyzer.analyze(lines: pending))
            pending.removeAll(keepingCapacity: true)
        }

        for element in elements {
            switch element {
            case .line(let line):
                pending.append(line)
            case .table(let rows):
                flush()
                blocks.append(.table(rows: rows))
            }
        }

        flush()
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
            let indent = Self.indent(of: nsRange, on: page)

            lines.append(
                TextLine(
                    text: Self.sanitize(substring),
                    fontSize: style.pointSize,
                    isBold: style.isBold,
                    indent: indent
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

    /// The horizontal offset of the first glyph of `range` on the page.
    private static func indent(of range: NSRange, on page: PDFPage) -> Double {
        guard range.length > 0,
              let selection = page.selection(for: NSRange(location: range.location, length: 1)) else {
            return 0
        }
        let bounds = selection.bounds(for: page)
        return bounds.isNull || bounds.isInfinite ? 0 : Double(bounds.minX)
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
