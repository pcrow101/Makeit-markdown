import CoreGraphics
import Testing
@testable import MarkdownKit

@Suite("Ruled tables")
struct RuledTableTests {

    private func cell(_ minX: CGFloat, _ maxX: CGFloat, bottom: CGFloat = 200) -> CGRect {
        CGRect(x: minX, y: bottom, width: maxX - minX, height: 40)
    }

    @Test("Touching cells of equal height form a header")
    func detectsHeaderStrip() {
        let grids = PDFRuledTable.grids(from: [cell(50, 90), cell(90, 130), cell(130, 200)])

        #expect(grids.first?.edges == [50, 90, 130, 200])
        #expect(grids.first?.columnCount == 3)
    }

    @Test("Separated cells are not a table")
    func ignoresSeparatedCells() {
        #expect(PDFRuledTable.grids(from: [cell(50, 90), cell(120, 160), cell(200, 240)]).isEmpty)
    }

    @Test("Two cells are too few to be a table")
    func ignoresShortStrips() {
        #expect(PDFRuledTable.grids(from: [cell(50, 90), cell(90, 130)]).isEmpty)
    }

    @Test("Strips are returned from the top of the page down")
    func ordersStripsTopFirst() {
        let low = [cell(50, 90, bottom: 100), cell(90, 130, bottom: 100), cell(130, 200, bottom: 100)]
        let high = [cell(60, 100, bottom: 400), cell(100, 140, bottom: 400), cell(140, 210, bottom: 400)]

        let grids = PDFRuledTable.grids(from: low + high)

        #expect(grids.map { $0.edges.first } == [60, 50])
    }

    @Test("Positions map onto the column that contains them")
    func mapsColumns() throws {
        let cells = [cell(50, 90), cell(90, 130), cell(130, 200)]
        let grid = try #require(PDFRuledTable.grids(from: cells).first)

        #expect(grid.column(at: 55) == 0)
        #expect(grid.column(at: 100) == 1)
        #expect(grid.column(at: 150) == 2)
    }
}
