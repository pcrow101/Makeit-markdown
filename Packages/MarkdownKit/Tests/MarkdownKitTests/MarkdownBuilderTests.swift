import Testing
@testable import MarkdownKit

@Suite("MarkdownBuilder")
struct MarkdownBuilderTests {

    @Test("An empty builder produces an empty document")
    func emptyDocument() {
        let builder = MarkdownBuilder()
        #expect(builder.isEmpty)
        #expect(builder.build().isEmpty)
    }

    @Test("Headings are clamped to the levels Markdown defines", arguments: [
        (0, "#"), (1, "#"), (3, "###"), (6, "######"), (9, "######")
    ])
    func headingLevelClamping(level: Int, expectedHashes: String) {
        var builder = MarkdownBuilder()
        builder.addHeading("Title", level: level)
        #expect(builder.build() == "\(expectedHashes) Title\n")
    }

    @Test("Blank headings and paragraphs are discarded")
    func blankContentIsDiscarded() {
        var builder = MarkdownBuilder()
        builder.addHeading("   ", level: 1)
        builder.addParagraph("\n  \n")
        builder.addList(["", "   "])
        #expect(builder.isEmpty)
    }

    @Test("Blocks are separated by a single blank line")
    func blockSeparation() {
        var builder = MarkdownBuilder()
        builder.addHeading("Title", level: 1)
        builder.addParagraph("Body text.")
        #expect(builder.build() == "# Title\n\nBody text.\n")
    }

    @Test("Paragraphs collapse internal line breaks")
    func paragraphCollapsesLineBreaks() {
        var builder = MarkdownBuilder()
        builder.addParagraph("One\n  Two  \n\nThree")
        #expect(builder.build() == "One Two Three\n")
    }

    // MARK: - Escaping

    @Test("Markdown significant characters are escaped")
    func inlineEscaping() {
        #expect(MarkdownBuilder.escape("a*b_c", inline: true) == "a\\*b\\_c")
        #expect(MarkdownBuilder.escape("<tag>", inline: true) == "\\<tag\\>")
        #expect(MarkdownBuilder.escape("[link]", inline: true) == "\\[link\\]")
        #expect(MarkdownBuilder.escape("back\\slash", inline: true) == "back\\\\slash")
    }

    @Test("Text that would open a block is escaped at the start of a paragraph")
    func leadingBlockMarkerEscaping() {
        var builder = MarkdownBuilder()
        builder.addParagraph("# not a heading")
        #expect(builder.build() == "\\# not a heading\n")
    }

    @Test("A leading number is escaped only when it would start an ordered list")
    func orderedListMarkerEscaping() {
        var builder = MarkdownBuilder()
        builder.addParagraph("1. not a list")
        #expect(builder.build() == "1\\. not a list\n")

        var other = MarkdownBuilder()
        other.addParagraph("1984 was a year")
        #expect(other.build() == "1984 was a year\n")
    }

    @Test("Headings do not receive block prefix escaping")
    func headingsSkipBlockEscaping() {
        var builder = MarkdownBuilder()
        builder.addHeading("- Results", level: 2)
        #expect(builder.build() == "## - Results\n")
    }

    // MARK: - Lists

    @Test("Unordered lists use a hyphen marker")
    func unorderedList() {
        var builder = MarkdownBuilder()
        builder.addList(["First", "Second"])
        #expect(builder.build() == "- First\n- Second\n")
    }

    @Test("Ordered lists are numbered from one")
    func orderedList() {
        var builder = MarkdownBuilder()
        builder.addList(["First", "Second"], ordered: true)
        #expect(builder.build() == "1. First\n2. Second\n")
    }

    @Test("Nested lists are indented by two spaces per level")
    func nestedListIndentation() {
        var builder = MarkdownBuilder()
        builder.addList(["Child"], indentLevel: 2)
        #expect(builder.build() == "    - Child\n")
    }

    @Test("A negative indent level is treated as the outermost level")
    func negativeIndentLevel() {
        var builder = MarkdownBuilder()
        builder.addList(["Item"], indentLevel: -3)
        #expect(builder.build() == "- Item\n")
    }

    // MARK: - Tables

    @Test("Tables emit a header, delimiter and body rows")
    func tableStructure() {
        var builder = MarkdownBuilder()
        builder.addTable(headers: ["Name", "Qty"], rows: [["Widget", "2"]])
        #expect(builder.build() == """
            | Name | Qty |
            | --- | --- |
            | Widget | 2 |

            """)
    }

    @Test("Column alignment is reflected in the delimiter row")
    func tableAlignment() {
        var builder = MarkdownBuilder()
        builder.addTable(
            headers: ["Left", "Middle", "Right"],
            rows: [],
            alignments: [.leading, .center, .trailing]
        )
        #expect(builder.build().contains("| :--- | :---: | ---: |"))
    }

    @Test("Rows are padded and truncated so the table stays rectangular")
    func tableRowNormalisation() {
        var builder = MarkdownBuilder()
        builder.addTable(
            headers: ["A", "B"],
            rows: [["only"], ["one", "two", "three"]]
        )
        let lines = builder.build().components(separatedBy: "\n")
        #expect(lines[2] == "| only |  |")
        #expect(lines[3] == "| one | two |")
    }

    @Test("Pipes inside cells are escaped so they do not split columns")
    func tableCellEscaping() {
        var builder = MarkdownBuilder()
        builder.addTable(headers: ["A"], rows: [["x | y"]])
        #expect(builder.build().contains("| x \\| y |"))
    }

    @Test("A table without headers is discarded")
    func tableWithoutHeaders() {
        var builder = MarkdownBuilder()
        builder.addTable(headers: [], rows: [["orphan"]])
        #expect(builder.isEmpty)
    }

    // MARK: - Other blocks

    @Test("Code fences widen to outlast backticks in the body")
    func codeFenceWidening() {
        var builder = MarkdownBuilder()
        builder.addCodeBlock("let a = ```b```", language: "swift")
        #expect(builder.build() == "````swift\nlet a = ```b```\n````\n")
    }

    @Test("Code block contents are not escaped")
    func codeBlockIsNotEscaped() {
        var builder = MarkdownBuilder()
        builder.addCodeBlock("a * b _ c")
        #expect(builder.build() == "```\na * b _ c\n```\n")
    }

    @Test("Block quotes prefix every line")
    func blockQuote() {
        var builder = MarkdownBuilder()
        builder.addBlockQuote("First\nSecond")
        #expect(builder.build() == "> First\n> Second\n")
    }

    @Test("Raw blocks bypass escaping")
    func rawBlock() {
        var builder = MarkdownBuilder()
        builder.addRawBlock("  **already markdown**  ")
        #expect(builder.build() == "**already markdown**\n")
    }

    @Test("Thematic breaks are emitted verbatim")
    func thematicBreak() {
        var builder = MarkdownBuilder()
        builder.addParagraph("Before")
        builder.addThematicBreak()
        builder.addParagraph("After")
        #expect(builder.build() == "Before\n\n---\n\nAfter\n")
    }
}
