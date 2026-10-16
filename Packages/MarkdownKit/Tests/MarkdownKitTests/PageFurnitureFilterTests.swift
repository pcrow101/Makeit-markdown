import Testing

@testable import MarkdownKit

@Suite("PageFurnitureFilter")
struct PageFurnitureFilterTests {

    /// Builds a page whose first line is a running header and whose last line
    /// is a running footer.
    private func page(header: String, body: [String], footer: String) -> [TextLine] {
        ([header] + body + [footer]).map { TextLine(text: $0) }
    }

    @Test("A header repeated on every page is removed")
    func removesRepeatedHeader() {
        let pages = (1...4).map { index in
            page(header: "Confidential", body: ["Body \(index)"], footer: "End \(index)")
        }

        let stripped = PageFurnitureFilter.strip(pages: pages)

        #expect(stripped.allSatisfy { !$0.contains { $0.text == "Confidential" } })
        #expect(stripped[0].contains { $0.text == "Body 1" })
    }

    @Test("A footer whose only difference is its page number is removed")
    func removesNumberedFooter() {
        let pages = (1...5).map { index in
            page(header: "Title", body: ["Body \(index)"], footer: "Page \(index) of 5")
        }

        let stripped = PageFurnitureFilter.strip(pages: pages)

        #expect(stripped.allSatisfy { !$0.contains { $0.text.hasPrefix("Page ") } })
    }

    @Test("Body content is never removed, even when it repeats")
    func keepsRepeatedBody() {
        // The repeated line sits well inside the page rather than at its edge.
        let pages = (1...4).map { index in
            page(
                header: "Header",
                body: ["Filler A", "Filler B", "Filler C", "Repeated note", "Filler D"],
                footer: "Footer \(index)"
            )
        }

        let stripped = PageFurnitureFilter.strip(pages: pages)

        #expect(stripped.allSatisfy { $0.contains { $0.text == "Repeated note" } })
    }

    @Test("A short document is left untouched")
    func ignoresShortDocuments() {
        // Two pages sharing a line is too weak a signal to act on.
        let pages = (1...2).map { index in
            page(header: "Confidential", body: ["Body \(index)"], footer: "Footer")
        }

        #expect(PageFurnitureFilter.strip(pages: pages) == pages)
    }

    @Test("A line appearing on too few pages is kept")
    func keepsInfrequentLines() {
        var pages = (1...5).map { index in
            [TextLine(text: "Unique \(index)")]
        }
        pages[0].insert(TextLine(text: "Occasional"), at: 0)
        pages[1].insert(TextLine(text: "Occasional"), at: 0)

        let stripped = PageFurnitureFilter.strip(pages: pages)
        let remaining = stripped.flatMap { $0 }.filter { $0.text == "Occasional" }

        #expect(remaining.count == 2)
    }

    @Test("A line repeated within one page cannot qualify on its own")
    func ignoresRepetitionWithinASinglePage() {
        var pages: [[TextLine]] = (1...4).map { [TextLine(text: "Body \($0)")] }
        pages[0] = (1...6).map { _ in TextLine(text: "Echo") }

        let stripped = PageFurnitureFilter.strip(pages: pages)

        #expect(stripped[0].contains { $0.text == "Echo" })
    }

    @Test("Normalisation ignores case and spacing")
    func normalisation() {
        #expect(
            PageFurnitureFilter.normalize(" Confidential ")
                == PageFurnitureFilter.normalize("CONFIDENTIAL")
        )
        #expect(
            PageFurnitureFilter.normalize("Chapter One")
                != PageFurnitureFilter.normalize("Chapter Two")
        )
        // Digits are significant unless they are explicitly ignored.
        #expect(
            PageFurnitureFilter.normalize("Page 1 of 20")
                != PageFurnitureFilter.normalize("Page 4 of 20")
        )
    }

    @Test("Digit insensitive normalisation matches numbered footers")
    func digitInsensitiveNormalisation() {
        #expect(
            PageFurnitureFilter.normalizeIgnoringDigits("Page 1 of 20")
                == PageFurnitureFilter.normalizeIgnoringDigits("page   4 of 20")
        )
        #expect(
            PageFurnitureFilter.normalizeIgnoringDigits("Section A")
                != PageFurnitureFilter.normalizeIgnoringDigits("Section B")
        )
    }

    @Test("The page edge never covers a whole page")
    func edgeDepthShrinksOnShortPages() {
        // Two edges of the returned depth must leave at least one interior line.
        for lineCount in 3...12 {
            #expect(PageFurnitureFilter.edgeDepth(pageLineCount: lineCount) * 2 < lineCount)
        }
    }

    @Test("Stripping is disabled through the conversion options")
    func respectsOption() {
        let options = ConversionOptions(stripRepeatedPageFurniture: false)
        #expect(options.stripRepeatedPageFurniture == false)
        #expect(ConversionOptions.default.stripRepeatedPageFurniture)
    }
}
