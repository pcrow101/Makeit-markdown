import Testing
@testable import MarkdownKit

@Suite("DocumentStructureAnalyzer")
struct DocumentStructureAnalyzerTests {

    private let analyzer = DocumentStructureAnalyzer(options: .default)

    // MARK: - Headings

    @Test("A markedly larger line becomes a top level heading")
    func titleDetection() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "Annual Report", fontSize: 24),
            TextLine(text: "Body text that carries the document.", fontSize: 12),
            TextLine(text: "More body text to establish the modal size.", fontSize: 12)
        ])
        #expect(blocks.first == .heading(text: "Annual Report", level: 1))
    }

    @Test("Heading levels follow the size ratio to body text", arguments: [
        (24.0, 1), (16.0, 2), (14.0, 3)
    ])
    func headingLevels(fontSize: Double, expectedLevel: Int) {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "Section", fontSize: fontSize),
            TextLine(text: "A long run of ordinary body text sets the modal size.", fontSize: 12),
            TextLine(text: "A second line of ordinary body text reinforces it.", fontSize: 12)
        ])
        #expect(blocks.first == .heading(text: "Section", level: expectedLevel))
    }

    @Test("Bold text at body size becomes a run-in heading")
    func boldRunInHeading() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "Summary", fontSize: 12, isBold: true),
            TextLine(text: "A long run of ordinary body text sets the modal size.", fontSize: 12)
        ])
        #expect(blocks.first == .heading(text: "Summary", level: 4))
    }

    @Test("A long line is prose even when it is set larger")
    func longLinesAreNotHeadings() {
        let long = String(repeating: "word ", count: 40)
        let blocks = analyzer.analyze(lines: [
            TextLine(text: long, fontSize: 24),
            TextLine(text: "Body text.", fontSize: 12)
        ])
        #expect(blocks.contains { if case .paragraph = $0 { return true } else { return false } })
        #expect(!blocks.contains { if case .heading = $0 { return true } else { return false } })
    }

    @Test("A line ending in sentence punctuation is not a heading")
    func sentencePunctuationBlocksHeadings() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "This looks big but ends in a stop.", fontSize: 24),
            TextLine(text: "Body text here.", fontSize: 12)
        ])
        #expect(!blocks.contains { if case .heading = $0 { return true } else { return false } })
    }

    @Test("Heading detection can be disabled")
    func headingDetectionDisabled() {
        let analyzer = DocumentStructureAnalyzer(
            options: ConversionOptions(detectHeadings: false)
        )
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "Annual Report", fontSize: 24),
            TextLine(text: "Body text.", fontSize: 12)
        ])
        #expect(!blocks.contains { if case .heading = $0 { return true } else { return false } })
    }

    // MARK: - Lists

    @Test("Bullet characters introduce unordered list items", arguments: ["•", "◦", "▪", "‣", "-", "*"])
    func bulletMarkers(marker: String) {
        let blocks = analyzer.analyze(lines: [TextLine(text: "\(marker) First item")])
        #expect(blocks == [.listItem(text: "First item", ordered: false, indentLevel: 0)])
    }

    @Test("Numeric and roman markers introduce ordered list items", arguments: ["1.", "2)", "iv."])
    func orderedMarkers(marker: String) {
        let blocks = analyzer.analyze(lines: [TextLine(text: "\(marker) An item")])
        #expect(blocks == [.listItem(text: "An item", ordered: true, indentLevel: 0)])
    }

    @Test("A hyphenated word is not mistaken for a list item")
    func hyphenatedWordIsNotAList() {
        let blocks = analyzer.analyze(lines: [TextLine(text: "-handed approach to the problem.")])
        #expect(blocks == [.paragraph(text: "-handed approach to the problem.")])
    }

    @Test("An initial followed by a period is not an ordered list")
    func initialIsNotAnOrderedList() {
        let blocks = analyzer.analyze(lines: [TextLine(text: "J. Smith wrote the report.")])
        #expect(blocks == [.paragraph(text: "J. Smith wrote the report.")])
    }

    @Test("Indented list items are nested")
    func listIndentation() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "• Parent", fontSize: 12, indent: 0),
            TextLine(text: "• Child", fontSize: 12, indent: 36)
        ])
        #expect(blocks == [
            .listItem(text: "Parent", ordered: false, indentLevel: 0),
            .listItem(text: "Child", ordered: false, indentLevel: 2)
        ])
    }

    @Test("List detection can be disabled")
    func listDetectionDisabled() {
        let analyzer = DocumentStructureAnalyzer(
            options: ConversionOptions(detectHeadings: false, detectLists: false)
        )
        let blocks = analyzer.analyze(lines: [TextLine(text: "• First item")])
        #expect(blocks == [.paragraph(text: "• First item")])
    }

    // MARK: - Paragraphs

    @Test("Wrapped lines are joined into one paragraph")
    func paragraphJoining() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "A sentence that was wrapped"),
            TextLine(text: "across two lines.")
        ])
        #expect(blocks == [.paragraph(text: "A sentence that was wrapped across two lines.")])
    }

    @Test("A sentence ending closes the paragraph")
    func paragraphTermination() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "First paragraph."),
            TextLine(text: "Second paragraph.")
        ])
        #expect(blocks == [
            .paragraph(text: "First paragraph."),
            .paragraph(text: "Second paragraph.")
        ])
    }

    @Test("Blank and whitespace-only lines are ignored")
    func blankLinesIgnored() {
        let blocks = analyzer.analyze(lines: [
            TextLine(text: "   "),
            TextLine(text: "Content."),
            TextLine(text: "")
        ])
        #expect(blocks == [.paragraph(text: "Content.")])
    }

    @Test("An empty page yields no blocks")
    func emptyInput() {
        #expect(analyzer.analyze(lines: []).isEmpty)
    }
}
