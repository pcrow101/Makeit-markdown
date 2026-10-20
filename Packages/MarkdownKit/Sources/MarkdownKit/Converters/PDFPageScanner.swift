import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Recovers the visual layout of a PDF page.
///
/// PDFKit's plain text for a page follows the order glyphs were written, which
/// interleaves the columns of a table into unreadable prose. Reading the page
/// through its line selections instead gives both the text and the position of
/// every visual line, which is enough to tell a table from a paragraph.
///
/// The scanner reports a page as a sequence of elements so that tabular regions
/// can be rendered as tables while everything else continues through the
/// ordinary structural analysis.
struct PDFPageScanner {

    /// One visual line of text and where it sits on the page.
    struct Fragment {
        var text: String
        var rect: CGRect
        var fontSize: Double
        var isBold: Bool
    }

    /// A group of fragments sharing a baseline.
    struct Band {
        var midY: CGFloat
        var fragments: [Fragment]
    }

    /// The result of scanning a page.
    enum Element {
        case line(TextLine)
        case table(rows: [[String]])
    }

    // MARK: - Tuning

    /// How far apart two fragments may sit vertically and still share a line.
    static let baselineTolerance = 0.5

    /// How far a fragment may sit from a column anchor and still belong to it.
    static let columnTolerance = 0.6

    /// How many lines must share an x position before it counts as a column.
    ///
    /// Requiring several independent lines is what stops an accidental
    /// alignment between two paragraphs from being read as a table.
    static let minimumColumnSupport = 2

    /// The fewest rows and columns a region needs to be treated as a table.
    ///
    /// A single row carries no tabular meaning and is usually an indented list,
    /// so it is deliberately excluded.
    static let minimumRows = 2
    static let minimumColumns = 2

    /// How much wider a gap must be than the one below it to count as the
    /// break between two rows.
    static let rowBreakFactor = 1.4

    /// How far apart the wrapped lines of one cell may sit, as a multiple of
    /// the line height. Anything wider is row spacing rather than wrapping.
    static let wrappedLineSpacingFactor = 1.6

    /// The multiple of the line height that marks a gap as a column boundary.
    ///
    /// Word spacing is a small fraction of the line height, so a gap of more
    /// than a whole line height is a deliberate separation rather than a space.
    static let columnGapFactor = 1.5

    /// How many unsplit lines may sit inside a table before it is taken to have
    /// ended. A wrapped cell produces one or two.
    static let maximumWrappedLines = 3

    /// How much larger than body text a lone line must be to count as a heading.
    static let headingFontRatio = 1.2

    /// The share of cells that must hold text for a grid to be a table.
    static let minimumFillRatio = 0.5

    // MARK: - Scanning

    /// Reads `page`, reporting tabular regions separately from ordinary lines.
    ///
    /// - Parameters:
    ///   - grids: Ruled tables found on the page, from top to bottom. They are
    ///     trusted over text alignment.
    ///   - detectAlignedTables: Whether to also look for tables from the
    ///     alignment of text alone, which is experimental.
    static func scan(
        page: PDFPage,
        grids: [RuledTableGrid] = [],
        detectAlignedTables: Bool = true
    ) -> [Element] {
        let fragments = fragments(on: page)
        guard !fragments.isEmpty else { return [] }

        let glyphHeight = median(fragments.map(\.rect.height))
        guard glyphHeight > 0 else { return [] }

        let context = ScanContext(
            glyphHeight: glyphHeight,
            bodyFontSize: median(fragments.map { CGFloat($0.fontSize) }).native,
            minimumIndent: fragments.map(\.rect.minX).min() ?? 0,
            pageRect: page.bounds(for: .cropBox),
            detectAlignedTables: detectAlignedTables
        )
        let bands = bands(from: fragments, glyphHeight: glyphHeight)

        return grids.isEmpty
            ? plainElements(for: bands[...], context: context)
            : ruledElements(bands: bands, grids: grids, context: context)
    }

    /// Measurements shared by every step of scanning one page.
    struct ScanContext {
        var glyphHeight: CGFloat
        var bodyFontSize: Double
        var minimumIndent: CGFloat
        var pageRect: CGRect
        var detectAlignedTables: Bool
    }

    /// Lines, plus tables recovered from text alignment when that is enabled.
    static func plainElements(for slice: ArraySlice<Band>, context: ScanContext) -> [Element] {
        guard context.detectAlignedTables else {
            return slice.map { .line(textLine(for: $0, minimumIndent: context.minimumIndent)) }
        }
        return alignedElements(
            for: Array(slice),
            glyphHeight: context.glyphHeight,
            minimumIndent: context.minimumIndent
        )
    }

    // MARK: - Fragments

    /// Every visual line on `page`, split where a wide horizontal gap suggests
    /// a column boundary.
    ///
    /// PDFKit sometimes reports each cell of a row as its own line selection and
    /// sometimes reports the whole row as one, depending on how the document was
    /// written. Splitting on glyph positions makes the result the same either
    /// way.
    static func fragments(on page: PDFPage) -> [Fragment] {
        guard let pageSelection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        let attributed = page.attributedString
        let geometryIndex = geometryIndexMap(for: attributed?.string as NSString?)

        return pageSelection.selectionsByLine().flatMap { selection -> [Fragment] in
            let whole = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !whole.isEmpty else { return [] }

            let rect = selection.bounds(for: page)
            guard !rect.isNull, !rect.isInfinite, rect.height > 0 else { return [] }

            let style = dominantStyle(of: selection, on: page, in: attributed)

            return segments(
                of: selection,
                on: page,
                lineHeight: rect.height,
                geometryIndex: geometryIndex
            ).map { segment in
                Fragment(
                    text: segment.text,
                    rect: CGRect(
                        x: segment.minX,
                        y: rect.minY,
                        width: max(segment.maxX - segment.minX, 0),
                        height: rect.height
                    ),
                    fontSize: style.pointSize,
                    isBold: style.isBold
                )
            }
        }
    }

    /// Maps a position in the page's text onto the index that
    /// `PDFPage.characterBounds(at:)` expects.
    ///
    /// The two are not the same. The text contains a line separator between
    /// lines, but the geometry does not count those separators, so the mapping
    /// drifts by one for every line break that precedes a character. Without
    /// this correction every line after the first is given the position of its
    /// neighbour.
    static func geometryIndexMap(for text: NSString?) -> [Int] {
        guard let text else { return [] }

        var map: [Int] = []
        map.reserveCapacity(text.length)
        var separators = 0

        for index in 0..<text.length {
            map.append(index - separators)
            let character = text.substring(with: NSRange(location: index, length: 1))
            if character.allSatisfy(\.isNewline) { separators += 1 }
        }

        return map
    }

    struct Segment {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
    }

    /// Splits a line into the runs of text separated by column sized gaps.
    ///
    /// The gap is measured between the visible glyphs on either side of it.
    /// A writer may separate columns either by moving the text position, which
    /// leaves a true gap, or by emitting one very wide space character, and
    /// measuring between visible glyphs covers both.
    static func segments(
        of selection: PDFSelection,
        on page: PDFPage,
        lineHeight: CGFloat,
        geometryIndex: [Int]
    ) -> [Segment] {
        guard let text = page.attributedString?.string as NSString? else { return [] }

        // A gap has to be far wider than the spaces between words before it is
        // read as a column boundary.
        let columnGap = lineHeight * columnGapFactor

        var segments: [Segment] = []
        var current = ""
        var minX: CGFloat = 0
        var maxX: CGFloat = 0
        var lastVisibleMaxX: CGFloat?
        var pendingSpace = false

        func close() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append(Segment(text: trimmed, minX: minX, maxX: maxX))
            }
            current = ""
            pendingSpace = false
        }

        for index in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: index, on: page)
            guard range.location >= 0, range.location + range.length <= text.length,
                  range.location + range.length <= geometryIndex.count else { continue }

            for offset in range.location..<(range.location + range.length) {
                let piece = text.substring(with: NSRange(location: offset, length: 1))
                if piece.allSatisfy(\.isNewline) { continue }

                if piece.allSatisfy(\.isWhitespace) {
                    pendingSpace = !current.isEmpty
                    continue
                }

                let bounds = page.characterBounds(at: geometryIndex[offset])
                guard !bounds.isNull, !bounds.isInfinite else { continue }

                if let previous = lastVisibleMaxX, bounds.minX - previous >= columnGap {
                    close()
                }

                if current.isEmpty {
                    minX = bounds.minX
                } else if pendingSpace {
                    current.append(" ")
                }

                pendingSpace = false
                current.append(piece)
                maxX = bounds.maxX
                lastVisibleMaxX = bounds.maxX
            }
        }

        close()
        return segments
    }

    private struct FontStyle {
        var pointSize: Double
        var isBold: Bool
    }

    /// The font covering the most characters of `selection`.
    private static func dominantStyle(
        of selection: PDFSelection,
        on page: PDFPage,
        in attributed: NSAttributedString?
    ) -> FontStyle {
        guard let attributed, attributed.length > 0 else {
            return FontStyle(pointSize: 12, isBold: false)
        }

        var tally: [Double: (length: Int, isBold: Bool)] = [:]

        for index in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: index, on: page)
            let clamped = NSRange(
                location: min(range.location, attributed.length),
                length: min(range.length, max(attributed.length - range.location, 0))
            )
            guard clamped.length > 0 else { continue }

            attributed.enumerateAttribute(.font, in: clamped, options: []) { value, subrange, _ in
                guard let font = value as? NSFont else { return }
                let size = Double(font.pointSize)
                let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                let existing = tally[size] ?? (length: 0, isBold: isBold)
                tally[size] = (length: existing.length + subrange.length, isBold: existing.isBold || isBold)
            }
        }

        // Ties are broken on the point size so that the result does not depend
        // on the order the dictionary happens to iterate in, which varies
        // between runs and would make conversion unrepeatable.
        guard let dominant = tally.max(by: { lhs, rhs in
            if lhs.value.length != rhs.value.length { return lhs.value.length < rhs.value.length }
            return lhs.key < rhs.key
        }) else {
            return FontStyle(pointSize: 12, isBold: false)
        }
        return FontStyle(pointSize: dominant.key, isBold: dominant.value.isBold)
    }

    // MARK: - Bands

    /// Groups fragments that share a baseline.
    static func bands(from fragments: [Fragment], glyphHeight: CGFloat) -> [Band] {
        var bands: [Band] = []
        let tolerance = glyphHeight * baselineTolerance

        for fragment in fragments.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let index = bands.indices.last,
               abs(bands[index].midY - fragment.rect.midY) <= tolerance {
                bands[index].fragments.append(fragment)
            } else {
                bands.append(Band(midY: fragment.rect.midY, fragments: [fragment]))
            }
        }

        return bands
    }

    /// Renders a band as a single line of text for the structural analyser.
    static func textLine(for band: Band, minimumIndent: CGFloat) -> TextLine {
        let ordered = band.fragments.sorted { $0.rect.minX < $1.rect.minX }
        let dominant = ordered.max { $0.text.count < $1.text.count } ?? ordered[0]

        return TextLine(
            text: ordered.map(\.text).joined(separator: " "),
            fontSize: dominant.fontSize,
            isBold: dominant.isBold,
            indent: Double((ordered.first?.rect.minX ?? minimumIndent) - minimumIndent),
            top: ordered.map { Double($0.rect.maxY) }.max()
        )
    }

    // MARK: - Helpers

    static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}
