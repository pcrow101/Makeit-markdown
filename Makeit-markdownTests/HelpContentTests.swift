import Foundation
import Testing
@testable import Makeit_markdown

@Suite("Help content")
struct HelpContentTests {

    @Test("Every topic has a title, a symbol and a body")
    func topicsAreComplete() {
        for topic in HelpTopic.allCases {
            #expect(!topic.title.isEmpty)
            #expect(!topic.symbol.isEmpty)
            #expect(!topic.body.isEmpty)
        }
    }

    @Test("The plan's five help sections are all present")
    func expectedTopics() {
        #expect(HelpTopic.allCases.count == 6)
        #expect(HelpTopic.allCases.map(\.id).contains("images"))
        #expect(HelpTopic.allCases.map(\.id).contains("gettingStarted"))
        #expect(HelpTopic.allCases.map(\.id).contains("commandLine"))
        #expect(HelpTopic.allCases.map(\.id).contains("troubleshooting"))
    }

    @Test("Topic identifiers are unique")
    func uniqueIdentifiers() {
        let ids = HelpTopic.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every code fence in the help text is closed")
    func codeFencesAreBalanced() {
        for topic in HelpTopic.allCases {
            let fences = topic.body
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("```") }
            #expect(fences.count.isMultiple(of: 2), "Unbalanced fences in \(topic.title)")
        }
    }

    @Test("Help pages parse into renderable blocks")
    func blocksParse() {
        for topic in HelpTopic.allCases {
            #expect(!HelpBlock.parse(topic.body).isEmpty)
        }
    }

    @Test("Fenced code is separated from prose")
    func codeBlocksAreExtracted() {
        let blocks = HelpBlock.parse(
            """
            Intro text.

            ```
            makeit-markdown report.pdf
            ```

            Closing text.
            """
        )

        #expect(blocks.count == 3)
        if case .code(let code) = blocks[1] {
            #expect(code == "makeit-markdown report.pdf")
        } else {
            Issue.record("Expected the middle block to be code.")
        }
    }

    @Test("The command line page documents every flag the tool accepts")
    func commandLineFlagsDocumented() {
        let body = HelpTopic.commandLine.body
        for flag in ["--output", "--stdout", "--recursive", "--overwrite",
                     "--no-tables", "--no-graphics", "--quiet"] {
            #expect(body.contains(flag), "\(flag) is not documented")
        }
    }

    @Test("The images page explains the toggle and the _images folder")
    func imagesDocumented() {
        let body = HelpTopic.images.body
        #expect(body.contains("_images"))
        #expect(body.contains("Extract pictures, drawings and charts"))
        #expect(body.contains("--no-graphics"))
        #expect(body.contains("Double-click"))
        #expect(body.contains("zoom"))
    }

    @Test("The formats page states that OCR is out of scope")
    func ocrIsDocumented() {
        #expect(HelpTopic.supportedFormats.body.lowercased().contains("recognition"))
    }

    @Test("Image window values with the same image are equal")
    func imageWindowValueEquality() {
        let first = ImageWindowValue(title: "Figure 1", data: Data([1, 2]))
        #expect(first == ImageWindowValue(title: "Figure 1", data: Data([1, 2])))
        #expect(first != ImageWindowValue(title: "Figure 1", data: Data([3])))
    }

    @Test("Zoom is clamped between fit-to-window and the maximum")
    func zoomIsClamped() {
        #expect(ImageZoom.zoomedOut(1) == 1)
        #expect(ImageZoom.zoomedIn(ImageZoom.range.upperBound) == ImageZoom.range.upperBound)
        #expect(ImageZoom.clamped(0.2) == 1)
        #expect(ImageZoom.clamped(100) == ImageZoom.range.upperBound)
        #expect(ImageZoom.zoomedIn(1) == ImageZoom.step)
    }
}
