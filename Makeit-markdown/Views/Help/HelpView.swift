import SwiftUI

/// The help window, shown from the Help menu.
struct HelpView: View {

    @State private var selection: HelpTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle("Help")
        } detail: {
            HelpPageView(topic: selection)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// A single rendered help page.
struct HelpPageView: View {

    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(topic.title)
                    .font(.largeTitle.weight(.semibold))

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(28)
        }
        .textSelection(.enabled)
        .navigationTitle(topic.title)
    }

    private var blocks: [HelpBlock] {
        HelpBlock.parse(topic.body)
    }
}

/// A paragraph or code block within a help page.
///
/// `AttributedString` does not render fenced code, so the Markdown is split
/// into blocks and code is laid out separately in a monospaced style.
enum HelpBlock {

    case prose(AttributedString)
    case code(String)

    @ViewBuilder var view: some View {
        switch self {
        case .prose(let text):
            Text(text)
                .font(.body)

        case .code(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Splits `markdown` into prose and fenced code blocks.
    static func parse(_ markdown: String) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushProse() {
            let text = proseLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            proseLines.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            blocks.append(.prose(attributed(from: text)))
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    flushProse()
                }
                inCode.toggle()
                continue
            }

            if inCode {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }

        flushProse()
        return blocks
    }

    private static func attributed(from markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)
    }
}

#Preview {
    HelpView()
}
