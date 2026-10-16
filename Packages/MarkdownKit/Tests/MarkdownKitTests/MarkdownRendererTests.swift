import Testing
@testable import MarkdownKit

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {

    @Test("Consecutive list items merge into a single list")
    func consecutiveItemsMerge() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(blocks: [
            .listItem(text: "First", ordered: false, indentLevel: 0),
            .listItem(text: "Second", ordered: false, indentLevel: 0)
        ])
        #expect(markdown == "- First\n- Second\n")
    }

    @Test("A change of list kind starts a new list")
    func listKindChangeSplits() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(blocks: [
            .listItem(text: "Bullet", ordered: false, indentLevel: 0),
            .listItem(text: "Number", ordered: true, indentLevel: 0)
        ])
        #expect(markdown == "- Bullet\n\n1. Number\n")
    }

    @Test("A change of depth starts a nested list")
    func listDepthChangeSplits() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(blocks: [
            .listItem(text: "Parent", ordered: false, indentLevel: 0),
            .listItem(text: "Child", ordered: false, indentLevel: 1)
        ])
        #expect(markdown == "- Parent\n\n  - Child\n")
    }

    @Test("A heading closes the list that precedes it")
    func headingFlushesList() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(blocks: [
            .listItem(text: "Item", ordered: false, indentLevel: 0),
            .heading(text: "Next", level: 2)
        ])
        #expect(markdown == "- Item\n\n## Next\n")
    }

    @Test("Page breaks are omitted by default")
    func pageBreaksOmitted() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(pages: [
            [.paragraph(text: "Page one.")],
            [.paragraph(text: "Page two.")]
        ])
        #expect(markdown == "Page one.\n\nPage two.\n")
    }

    @Test("Page breaks are emitted between pages when requested")
    func pageBreaksEmitted() {
        let renderer = MarkdownRenderer(options: ConversionOptions(insertPageBreaks: true))
        let markdown = renderer.render(pages: [
            [.paragraph(text: "Page one.")],
            [.paragraph(text: "Page two.")]
        ])
        #expect(markdown == "Page one.\n\n---\n\nPage two.\n")
    }

    @Test("No page break precedes the first page")
    func noLeadingPageBreak() {
        let renderer = MarkdownRenderer(options: ConversionOptions(insertPageBreaks: true))
        let markdown = renderer.render(pages: [[.paragraph(text: "Only page.")]])
        #expect(markdown == "Only page.\n")
    }

    @Test("Empty pages do not produce stray separators")
    func emptyPagesSkipped() {
        let renderer = MarkdownRenderer(options: ConversionOptions(insertPageBreaks: true))
        let markdown = renderer.render(pages: [
            [.paragraph(text: "Content.")],
            [],
            [.paragraph(text: "More.")]
        ])
        #expect(markdown == "Content.\n\n---\n\nMore.\n")
    }

    @Test("A document with no blocks renders as an empty string")
    func emptyDocument() {
        let renderer = MarkdownRenderer(options: .default)
        #expect(renderer.render(pages: []).isEmpty)
        #expect(renderer.render(blocks: []).isEmpty)
    }

    @Test("Normalisation terminates the document with exactly one newline")
    func singleTrailingNewline() {
        let renderer = MarkdownRenderer(options: .default)
        let markdown = renderer.render(blocks: [.paragraph(text: "Body.")])
        #expect(markdown.hasSuffix("Body.\n"))
        #expect(!markdown.hasSuffix("\n\n"))
    }
}
