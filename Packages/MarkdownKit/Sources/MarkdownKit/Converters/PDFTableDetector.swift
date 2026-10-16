import CoreGraphics
import Foundation
import PDFKit

/// Recovers tables from the geometry of a scanned page.
///
/// A table is recognised by alignment: several lines placing their pieces at
/// the same horizontal positions. Everything here works on the bands produced
/// by ``PDFPageScanner`` rather than on the page itself, which keeps the
/// heuristics testable without a document.
extension PDFPageScanner {

    /// Whether recovered rows are convincing enough to emit as a table.
    static func isTable(_ rows: [[String]]) -> Bool {
        guard rows.count >= minimumRows, let width = rows.first?.count, width >= minimumColumns else {
            return false
        }

        // An indented list puts its markers in one column and its text in
        // another, which looks tabular but reads far better as a list.
        let leadingCells = rows.compactMap { $0.first?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if leadingCells.count >= minimumRows,
           leadingCells.allSatisfy({ ListMarker.isBareMarker($0) }) {
            return false
        }

        // A real table is mostly populated. A sparse grid means the region
        // gathered unrelated content, or that the source used merged cells the
        // scan cannot represent, and prose is the safer rendering of both.
        let total = rows.reduce(0) { $0 + $1.count }
        let filled = rows.reduce(0) { sum, row in
            sum + row.count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        guard total > 0, Double(filled) / Double(total) >= minimumFillRatio else { return false }

        return true
    }

    /// Runs of lines that are worth testing for tabular structure.
    ///
    /// A line split into several pieces is the evidence that a table is
    /// present. Lines that were not split are allowed inside a run, because a
    /// cell whose text has wrapped produces one.
    static func candidateRegions(in bands: [Band]) -> [ClosedRange<Int>] {
        let isMulti = bands.map { $0.fragments.count >= minimumColumns }
        var regions: [ClosedRange<Int>] = []
        var index = 0

        while index < bands.count {
            guard isMulti[index] else {
                index += 1
                continue
            }

            var end = index
            var probe = index
            var multiCount = 0
            var runOfSingles = 0

            while probe < bands.count {
                if isMulti[probe] {
                    multiCount += 1
                    end = probe
                    runOfSingles = 0
                } else {
                    runOfSingles += 1
                    if runOfSingles > maximumWrappedLines { break }
                }
                probe += 1
            }

            if multiCount >= minimumRows {
                regions.append(index...end)
            }
            index = max(end + 1, index + 1)
        }

        return regions
    }
    // MARK: - Columns

    /// The x positions shared by enough lines to be treated as table columns.
    static func columnAnchors(in bands: [Band], glyphHeight: CGFloat) -> [CGFloat] {
        let tolerance = glyphHeight * columnTolerance
        var counts: [(x: CGFloat, bands: Int)] = []

        // Only lines already split into several pieces can evidence a column.
        for band in bands where band.fragments.count >= minimumColumns {
            for leftEdge in band.fragments.map(\.rect.minX) {
                if let index = counts.firstIndex(where: { abs($0.x - leftEdge) <= tolerance }) {
                    counts[index].bands += 1
                } else {
                    counts.append((x: leftEdge, bands: 1))
                }
            }
        }

        // Within a region a column only has to recur, since the region was
        // already selected for looking tabular.
        return counts.filter { $0.bands >= minimumColumnSupport }.map(\.x).sorted()
    }

    private static func anchorIndex(
        for leftEdge: CGFloat,
        anchors: [CGFloat],
        tolerance: CGFloat
    ) -> Int? {
        anchors.firstIndex { abs($0 - leftEdge) <= tolerance }
    }

    /// Whether a line places at least two pieces on known columns.
    private static func isTabular(_ band: Band, anchors: [CGFloat], tolerance: CGFloat) -> Bool {
        band.fragments
            .compactMap { anchorIndex(for: $0.rect.minX, anchors: anchors, tolerance: tolerance) }
            .count >= minimumColumns
    }

    // MARK: - Regions

    /// The ranges of bands that form tabular regions.
    static func tableRegions(
        in bands: [Band],
        anchors: [CGFloat],
        glyphHeight: CGFloat
    ) -> [ClosedRange<Int>] {
        let tolerance = glyphHeight * columnTolerance
        var regions: [ClosedRange<Int>] = []
        var index = 0

        while index < bands.count {
            guard isTabular(bands[index], anchors: anchors, tolerance: tolerance) else {
                index += 1
                continue
            }

            var end = index
            var tabularCount = 0
            var probe = index

            while probe < bands.count {
                if isTabular(bands[probe], anchors: anchors, tolerance: tolerance) {
                    tabularCount += 1
                    end = probe
                } else if bands[probe].fragments.allSatisfy({
                    anchorIndex(for: $0.rect.minX, anchors: anchors, tolerance: tolerance) != nil
                }) {
                    // A continuation line belonging to a wrapped cell.
                } else {
                    break
                }
                probe += 1
            }

            if tabularCount >= minimumRows {
                regions.append(index...end)
            }
            index = max(end + 1, index + 1)
        }

        return regions
    }

    /// The vertical gap above which one row ends and the next begins.
    ///
    /// A cell whose text has wrapped puts its lines about a line height apart,
    /// closer than the rows are, so the gaps fall into groups and the threshold
    /// belongs above the smallest one. The first proportional jump is taken
    /// rather than the widest, because the widest is often an unrelated break
    /// before a sub heading, and using it would put the threshold above the row
    /// spacing and merge every row into one.
    ///
    /// The smallest group also has to look like wrapped text. Without that
    /// check a table where nothing wraps, but which contains one wide break,
    /// would treat its ordinary row spacing as wrapping.
    ///
    /// - Returns: The threshold, or zero when no group looks like wrapped
    ///   lines, meaning every line is a row of its own.
    static func rowBreakThreshold(for gaps: [CGFloat], lineHeight: CGFloat) -> CGFloat {
        let sorted = gaps.filter { $0 > 0 }.sorted()
        guard sorted.count >= 2 else { return 0 }

        for index in 1..<sorted.count {
            let previous = max(sorted[index - 1], 0.01)
            guard sorted[index] / previous >= rowBreakFactor else { continue }

            let below = sorted[0..<index]
            let mean = below.reduce(0, +) / CGFloat(below.count)
            guard mean <= lineHeight * wrappedLineSpacingFactor else { return 0 }

            return (sorted[index] + sorted[index - 1]) / 2
        }

        return 0
    }

    /// Whether `first` comes before `second` in reading order.
    ///
    /// Sorting on the vertical position alone leaves pieces that share a line
    /// in whatever order they were collected, so the horizontal position breaks
    /// the tie and keeps a cell's text in the order it was written.
    static func readsBefore(_ first: Fragment, _ second: Fragment) -> Bool {
        if first.rect.midY == second.rect.midY {
            return first.rect.minX < second.rect.minX
        }
        return first.rect.midY > second.rect.midY
    }

    /// Splits a tabular region into rows and merges wrapped cells.
    static func tableRows(
        in slice: ArraySlice<Band>,
        anchors: [CGFloat],
        glyphHeight: CGFloat
    ) -> [[String]] {
        let bands = Array(slice)
        guard !bands.isEmpty else { return [] }

        let tolerance = glyphHeight * columnTolerance
        let gaps = zip(bands, bands.dropFirst()).map { $0.midY - $1.midY }.filter { $0 > 0 }
        let rowBreak = rowBreakThreshold(for: gaps, lineHeight: glyphHeight)

        var rows: [[Band]] = [[bands[0]]]
        for (previous, band) in zip(bands, bands.dropFirst()) {
            if previous.midY - band.midY > rowBreak {
                rows.append([band])
            } else {
                rows[rows.count - 1].append(band)
            }
        }

        let cells = rows.map { row in
            var byColumn: [Int: [Fragment]] = [:]
            for band in row {
                for fragment in band.fragments {
                    guard let column = anchorIndex(
                        for: fragment.rect.minX,
                        anchors: anchors,
                        tolerance: tolerance
                    ) else { continue }
                    byColumn[column, default: []].append(fragment)
                }
            }

            return (0..<anchors.count).map { column in
                (byColumn[column] ?? [])
                    .sorted { readsBefore($0, $1) }
                    .map(\.text)
                    .joined(separator: " ")
            }
        }

        return pruningEmptyRows(pruningEmptyColumns(cells))
    }

    /// Drops rows that hold no text at all.
    ///
    /// The first row of a table becomes its Markdown header, so a leading blank
    /// row would render the table with an empty heading. Blank rows carry
    /// nothing wherever they appear, so all of them go.
    static func pruningEmptyRows(_ rows: [[String]]) -> [[String]] {
        rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    /// Drops columns that are empty in every row.
    ///
    /// Column anchors are gathered across a whole page, so a page holding more
    /// than one table produces the union of their columns. Without pruning,
    /// every table would carry the other tables' columns as empty padding.
    static func pruningEmptyColumns(_ rows: [[String]]) -> [[String]] {
        guard let width = rows.first?.count, width > 0 else { return rows }

        let occupied = (0..<width).filter { column in
            rows.contains { row in
                column < row.count && !row[column].trimmingCharacters(in: .whitespaces).isEmpty
            }
        }

        guard occupied.count != width else { return rows }
        return rows.map { row in occupied.map { $0 < row.count ? row[$0] : "" } }
    }
}
