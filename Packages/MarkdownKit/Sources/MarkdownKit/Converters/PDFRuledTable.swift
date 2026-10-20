import CoreGraphics
import Foundation
import PDFKit

/// A table whose header cells are drawn as adjacent filled rectangles.
///
/// Ruling and cell shading are direct evidence of table structure, so they are
/// trusted far more than the alignment of text.
struct RuledTableGrid: Equatable {

    /// The x positions of the column boundaries, left to right.
    var edges: [CGFloat]

    /// The vertical extent of the header row.
    var header: ClosedRange<CGFloat>

    var columnCount: Int { edges.count - 1 }

    /// A grid carried over from the previous page, which has no header of its own.
    var isContinuation: Bool { header.lowerBound == .greatestFiniteMagnitude }

    /// The column that contains the horizontal `position`.
    func column(at position: CGFloat) -> Int {
        let interior = edges.dropFirst().dropLast()
        return interior.filter { $0 <= position + 1 }.count
    }
}

/// A ruled table that runs on to the next page.
///
/// Later pages of a long table often repeat no header and draw no cells, so the
/// columns and header of the first page are carried forward.
struct RuledTableContinuation {

    var edges: [CGFloat]
    var header: [String]

    /// The grid to read the next page with.
    var grid: RuledTableGrid {
        RuledTableGrid(edges: edges, header: .greatestFiniteMagnitude ... .greatestFiniteMagnitude)
    }

    /// Gives the first table of a continuation page the header of the original.
    func completing(_ elements: [PDFPageScanner.Element]) -> [PDFPageScanner.Element] {
        var done = false
        return elements.map { element in
            guard !done, case .table(let rows) = element, rows.first?.count == header.count else {
                return element
            }
            done = true
            return .table(rows: [header] + rows)
        }
    }

    /// The continuation implied by a page, when its table reaches the page end.
    ///
    /// - Parameters:
    ///   - ownGrid: The ruled table found on the page itself.
    ///   - previous: The continuation the page was read with, if any.
    static func after(
        elements: [PDFPageScanner.Element],
        ownGrid: RuledTableGrid?,
        previous: RuledTableContinuation?,
        pageRect: CGRect
    ) -> RuledTableContinuation? {
        guard let tableIndex = elements.lastIndex(where: { element in
            if case .table = element { return true }
            return false
        }), case .table(let rows) = elements[tableIndex], let firstRow = rows.first else { return nil }

        let margin = pageRect.height * 0.1
        let reachesEnd = elements[(tableIndex + 1)...].allSatisfy { element in
            guard case .line(let line) = element, let top = line.top else { return false }
            return top < pageRect.minY + margin || top > pageRect.maxY - margin
        }
        guard reachesEnd else { return nil }

        if let ownGrid {
            return RuledTableContinuation(edges: ownGrid.edges, header: firstRow)
        }
        return previous
    }
}

enum PDFRuledTable {

    private static let minimumColumns = 3
    private static let maximumHeaderHeight: CGFloat = 120
    private static let adjacencyTolerance: CGFloat = 1.5

    /// The header strips of the ruled tables on `page`, from top to bottom.
    static func grids(on page: PDFPage) -> [RuledTableGrid] {
        guard let cgPage = page.pageRef, cgPage.rotationAngle == 0 else { return [] }

        let scan = PDFContentScan()
        scan.run(page: cgPage)

        let cells = scan.pieces.filter {
            $0.kind == .vector && $0.rect.width > 8 && $0.rect.height > 6
                && $0.rect.height <= maximumHeaderHeight
        }
        return grids(from: cells.map(\.rect))
    }

    /// Every row of at least three touching cells of equal height, top first.
    static func grids(from rects: [CGRect]) -> [RuledTableGrid] {
        let rows = Dictionary(grouping: rects) { rect in
            "\(Int((rect.minY * 2).rounded()))/\(Int((rect.maxY * 2).rounded()))"
        }

        var grids: [RuledTableGrid] = []
        for row in rows.values where row.count >= minimumColumns {
            guard let chain = longestChain(of: row.sorted { $0.minX < $1.minX }),
                  chain.count >= minimumColumns,
                  let first = chain.first else { continue }

            grids.append(
                RuledTableGrid(edges: [first.minX] + chain.map(\.maxX), header: first.minY...first.maxY)
            )
        }
        return grids.sorted { $0.header.upperBound > $1.header.upperBound }
    }

    private static func longestChain(of sorted: [CGRect]) -> [CGRect]? {
        var best: [CGRect] = []
        var chain: [CGRect] = []

        for rect in sorted {
            if let last = chain.last, abs(rect.minX - last.maxX) <= adjacencyTolerance {
                chain.append(rect)
            } else {
                chain = [rect]
            }
            if chain.count > best.count { best = chain }
        }
        return best.isEmpty ? nil : best
    }
}

extension PDFPageScanner {

    /// How many line heights of empty space end a ruled table.
    private static let ruledTableGapFactor: CGFloat = 6

    /// How many line heights may separate an unshaded header from the first row.
    private static let headerGapFactor: CGFloat = 3.5

    /// The share of the page height treated as header and footer margin.
    private static let pageMarginShare: CGFloat = 0.05

    /// The bands that form the ruled table, split from those before and after.
    struct RuledSplit {
        var before: ArraySlice<Band>
        var header: ArraySlice<Band>
        var body: ArraySlice<Band>
        var after: ArraySlice<Band>
    }

    static func splitRuled(
        bands: [Band],
        grid: RuledTableGrid,
        context: ScanContext
    ) -> RuledSplit {
        let pageRect = context.pageRect
        let margin = pageRect.height * pageMarginShare

        // The header occupies bands[headerStart..<headerEnd]; the body follows.
        var headerStart: Int
        var headerEnd: Int
        var bodyStart: Int
        var previous: CGFloat

        if grid.isContinuation {
            // There is no header to find, so the body begins below the margin.
            headerStart = bands.firstIndex { $0.midY <= pageRect.maxY - margin } ?? bands.count
            headerEnd = headerStart
            bodyStart = headerStart
            previous = bands.indices.contains(bodyStart) ? bands[bodyStart].midY : 0
        } else {
            let stripStart = bands.firstIndex { $0.midY <= grid.header.upperBound } ?? bands.count
            var stripEnd = stripStart
            while stripEnd < bands.count, bands[stripEnd].midY >= grid.header.lowerBound {
                stripEnd += 1
            }

            if let line = boldHeaderLine(above: stripStart, in: bands, context: context) {
                // The strip is an ordinary row, so the header sits above it.
                headerStart = line
                headerEnd = stripStart
                bodyStart = stripStart
                previous = bands[line].midY
            } else {
                headerStart = stripStart
                headerEnd = stripEnd
                bodyStart = stripEnd
                previous = grid.header.lowerBound
            }
        }

        let floor = pageRect.minY + margin
        var end = bodyStart
        while end < bands.count {
            let band = bands[end]
            guard band.midY > floor,
                  previous - band.midY <= context.glyphHeight * ruledTableGapFactor,
                  !isHeadingBand(band, bodyFontSize: context.bodyFontSize) else { break }
            previous = band.midY
            end += 1
        }

        return RuledSplit(
            before: bands[..<headerStart],
            header: bands[headerStart..<headerEnd],
            body: bands[bodyStart..<end],
            after: bands[end...]
        )
    }

    /// The index of a bold, multi-column line sitting just above a strip.
    ///
    /// Tables often shade only their body rows, leaving the header unshaded. A
    /// bold line of several pieces directly above the first shaded row is that
    /// header.
    private static func boldHeaderLine(above index: Int, in bands: [Band], context: ScanContext) -> Int? {
        guard index > 0, index < bands.count else { return nil }

        let candidate = bands[index - 1]
        let gap = candidate.midY - bands[index].midY

        guard candidate.fragments.count >= minimumColumns,
              candidate.fragments.allSatisfy(\.isBold),
              gap <= context.glyphHeight * headerGapFactor,
              !isHeadingBand(candidate, bodyFontSize: context.bodyFontSize) else { return nil }
        return index - 1
    }

    /// Whether the first body line begins within the table's columns.
    ///
    /// A page that continues a table should start with a row. Without this
    /// check, any text following a table at the end of a page would be pulled
    /// into it.
    static func startsInsideTable(_ body: ArraySlice<Band>, grid: RuledTableGrid) -> Bool {
        guard grid.isContinuation else { return true }
        guard let start = body.first?.fragments.map(\.rect.minX).min(),
              let first = grid.edges.first, let last = grid.edges.last else { return false }
        return start >= first - 2 && start < last
    }

    /// Builds table rows by placing each fragment in the column it starts in.
    static func ruledRows(split: RuledSplit, grid: RuledTableGrid, glyphHeight: CGFloat) -> [[String]] {
        func cells(for bands: [Band]) -> [String] {
            var columns = [[Fragment]](repeating: [], count: grid.columnCount)
            for fragment in bands.flatMap(\.fragments) {
                columns[grid.column(at: fragment.rect.minX)].append(fragment)
            }
            return columns.map { column in
                column.sorted { readsBefore($0, $1) }.map(\.text).joined(separator: " ")
            }
        }

        let body = Array(split.body)
        let gaps = zip(body, body.dropFirst()).map { $0.midY - $1.midY }
        let breakAt = rowBreakThreshold(for: gaps, lineHeight: glyphHeight)

        var groups: [[Band]] = []
        for (index, band) in body.enumerated() {
            if index > 0, body[index - 1].midY - band.midY > breakAt {
                groups.append([band])
            } else if groups.isEmpty {
                groups.append([band])
            } else {
                groups[groups.count - 1].append(band)
            }
        }

        let rows = [cells(for: Array(split.header))] + groups.map(cells)
        return rows.filter { row in row.contains { !$0.isEmpty } }
    }

    /// Reads a page whose tables are marked out by ruled header cells.
    ///
    /// Each table runs from its header to the next heading, gap or page margin.
    /// Strips that fall inside a table already read are its row shading.
    static func ruledElements(
        bands: [Band],
        grids: [RuledTableGrid],
        context: ScanContext
    ) -> [Element] {
        var elements: [Element] = []
        var remaining = bands[...]

        for grid in grids {
            // A continuation grid has no header of its own to lie above the text.
            guard let top = remaining.first?.midY,
                  grid.isContinuation || top >= grid.header.lowerBound else { continue }

            let split = splitRuled(bands: Array(remaining), grid: grid, context: context)
            let rows = ruledRows(split: split, grid: grid, glyphHeight: context.glyphHeight)

            let required = grid.isContinuation ? 1 : minimumRows
            guard rows.count >= required, startsInsideTable(split.body, grid: grid) else { continue }

            elements += boldHeaderTables(in: split.before, context: context)
            elements.append(.table(rows: rows))
            remaining = split.after
        }

        return elements + boldHeaderTables(in: remaining, context: context)
    }

    // MARK: - Unshaded tables

    /// Whether `band` looks like the bold header row of a table.
    private static func isBoldHeaderBand(_ band: Band, context: ScanContext) -> Bool {
        band.fragments.count >= 4
            && band.fragments.allSatisfy(\.isBold)
            && !isHeadingBand(band, bodyFontSize: context.bodyFontSize)
    }

    /// Finds tables that have a bold header row but no shaded cells.
    ///
    /// An empty table, such as a list of issues with none found, draws nothing
    /// but its header and a line of text, so there is no ruling to detect. The
    /// header is trusted instead, and the lines under it become its rows.
    static func boldHeaderTables(in slice: ArraySlice<Band>, context: ScanContext) -> [Element] {
        guard let start = slice.firstIndex(where: { isBoldHeaderBand($0, context: context) }) else {
            return plainElements(for: slice, context: context)
        }

        var end = start + 1
        var previous = slice[start].midY
        while end < slice.endIndex {
            let band = slice[end]
            guard !band.fragments.allSatisfy(\.isBold),
                  !isHeadingBand(band, bodyFontSize: context.bodyFontSize),
                  previous - band.midY <= context.glyphHeight * headerGapFactor else { break }
            previous = band.midY
            end += 1
        }

        let before = plainElements(for: slice[..<start], context: context)
        guard end > start + 1 else {
            let header = plainElements(for: slice[start..<(start + 1)], context: context)
            return before + header + boldHeaderTables(in: slice[(start + 1)...], context: context)
        }

        let edges = slice[start].fragments.map(\.rect.minX).sorted()
        func cells(of band: Band) -> [String] {
            var columns = [[Fragment]](repeating: [], count: edges.count)
            for fragment in band.fragments {
                let column = edges.lastIndex { $0 <= fragment.rect.minX + 2 } ?? 0
                columns[column].append(fragment)
            }
            return columns.map { $0.sorted { readsBefore($0, $1) }.map(\.text).joined(separator: " ") }
        }

        let rows = slice[start..<end].map(cells(of:))
        return before + [.table(rows: rows)]
            + boldHeaderTables(in: slice[end...], context: context)
    }
}
