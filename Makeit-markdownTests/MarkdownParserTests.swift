import Testing

@testable import Makeit_markdown

@Suite("MarkdownParser")
struct MarkdownParserTests {

    // MARK: - Tables

    @Test("A table becomes a table block")
    func parsesTable() {
        let blocks = MarkdownParser.parse("""
            | Key | Status |
            | --- | --- |
            | AB-1 | Open |
            | AB-2 | Closed |
            """)

        #expect(blocks.count == 1)
        #expect(
            blocks.first == .table(
                headers: ["Key", "Status"],
                rows: [["AB-1", "Open"], ["AB-2", "Closed"]]
            )
        )
    }

    @Test("A table is separated from the text around it")
    func separatesTableFromProse() {
        let blocks = MarkdownParser.parse("""
            Before the table.

            | Key | Status |
            | --- | --- |
            | AB-1 | Open |

            After the table.
            """)

        #expect(blocks.count == 3)
        #expect(blocks.first == .paragraph(text: "Before the table."))
        #expect(blocks.last == .paragraph(text: "After the table."))
    }

    @Test("Pipes inside a cell do not split it")
    func respectsEscapedPipes() {
        // The converter escapes pipes found in the source document.
        let blocks = MarkdownParser.parse("""
            | Name | Note |
            | --- | --- |
            | Beacons \\| Mobile | Fine |
            """)

        guard case .table(_, let rows) = blocks.first else {
            Issue.record("expected a table")
            return
        }
        #expect(rows == [["Beacons \\| Mobile", "Fine"]])
    }

    @Test("Rows are padded and truncated to the header width")
    func keepsTableRectangular() {
        let blocks = MarkdownParser.parse("""
            | A | B | C |
            | --- | --- | --- |
            | 1 |
            | 1 | 2 | 3 | 4 |
            """)

        guard case .table(let headers, let rows) = blocks.first else {
            Issue.record("expected a table")
            return
        }
        #expect(headers.count == 3)
        #expect(rows.allSatisfy { $0.count == 3 })
        #expect(rows.first == ["1", "", ""])
    }

    @Test("A row of pipes without a delimiter is not a table")
    func requiresDelimiterRow() {
        let blocks = MarkdownParser.parse("| not | really a table |")

        #expect(blocks.count == 1)
        if case .table = blocks.first {
            Issue.record("a lone row should not parse as a table")
        }
    }

    @Test("A delimiter row may carry alignment colons")
    func acceptsAlignmentColons() {
        let blocks = MarkdownParser.parse("""
            | A | B |
            | :--- | ---: |
            | 1 | 2 |
            """)

        guard case .table = blocks.first else {
            Issue.record("expected a table")
            return
        }
    }

    // MARK: - Other blocks

    @Test("Headings record their level")
    func parsesHeadings() {
        let blocks = MarkdownParser.parse("""
            # One

            ### Three
            """)

        #expect(blocks == [
            .heading(level: 1, text: "One"),
            .heading(level: 3, text: "Three")
        ])
    }

    @Test("A hash without a space is not a heading")
    func requiresSpaceAfterHash() {
        let blocks = MarkdownParser.parse("#NotAHeading")
        #expect(blocks == [.paragraph(text: "#NotAHeading")])
    }

    @Test("Wrapped lines join into one paragraph")
    func joinsParagraphLines() {
        let blocks = MarkdownParser.parse("""
            The first line
            continues here.
            """)

        #expect(blocks == [.paragraph(text: "The first line continues here.")])
    }

    @Test("Bulleted and numbered lists are distinguished")
    func parsesLists() {
        let bulleted = MarkdownParser.parse("- One\n- Two")
        #expect(bulleted == [
            .list(
                items: [
                    MarkdownBlock.Item(text: "One", depth: 0),
                    MarkdownBlock.Item(text: "Two", depth: 0)
                ],
                ordered: false
            )
        ])

        let numbered = MarkdownParser.parse("1. One\n2. Two")
        guard case .list(_, let ordered) = numbered.first else {
            Issue.record("expected a list")
            return
        }
        #expect(ordered)
    }

    @Test("Indentation becomes list depth")
    func recordsListDepth() {
        let blocks = MarkdownParser.parse("- One\n  - Nested")

        guard case .list(let items, _) = blocks.first else {
            Issue.record("expected a list")
            return
        }
        #expect(items.map(\.depth) == [0, 1])
    }

    @Test("A fenced code block keeps its lines")
    func parsesCode() {
        let blocks = MarkdownParser.parse("""
            ```swift
            let value = 1
            let other = 2
            ```
            """)

        #expect(blocks == [.code(text: "let value = 1\nlet other = 2", language: "swift")])
    }

    @Test("A rule of dashes is a thematic break")
    func parsesThematicBreak() {
        #expect(MarkdownParser.parse("---") == [.thematicBreak])
    }

    @Test("Quoted lines join into one quote")
    func parsesQuote() {
        #expect(MarkdownParser.parse("> One\n> Two") == [.quote(text: "One Two")])
    }

    @Test("An image line becomes an image block, with or without angle brackets")
    func parsesImages() {
        #expect(MarkdownParser.parse("![Figure 1 (page 2)](<My Doc_images/page-2-figure-1.png>)") == [
            .image(alt: "Figure 1 (page 2)", path: "My Doc_images/page-2-figure-1.png")
        ])
        #expect(MarkdownParser.parse("![](a/b.png)") == [.image(alt: "", path: "a/b.png")])
    }

    @Test("An image between paragraphs stays separate")
    func imageBetweenParagraphs() {
        let blocks = MarkdownParser.parse("Before\n![Fig](<x_images/f.png>)\nAfter")
        #expect(blocks == [
            .paragraph(text: "Before"),
            .image(alt: "Fig", path: "x_images/f.png"),
            .paragraph(text: "After")
        ])
    }

    @Test("An empty document yields no blocks")
    func handlesEmptyInput() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("\n\n   \n").isEmpty)
    }

    @Test("Converted output parses into the expected shape")
    func parsesRealisticDocument() {
        let blocks = MarkdownParser.parse("""
            # Report

            An opening paragraph.

            ## Issues

            | Key | Status |
            | --- | --- |
            | AB-1 | Open |

            - A closing point
            """)

        #expect(blocks.count == 5)
        #expect(blocks.contains { if case .table = $0 { return true } else { return false } })
    }
}
