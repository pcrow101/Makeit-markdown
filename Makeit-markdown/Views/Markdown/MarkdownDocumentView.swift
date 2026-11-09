import MarkdownKit
import SwiftUI

/// Draws parsed Markdown, including tables.
///
/// Each block is rendered with the view that suits it, and inline styling
/// within a block is handled by `AttributedString`, which is reliable at that
/// level.
struct MarkdownDocumentView: View {

    let markdown: String

    /// Files the Markdown refers to, such as extracted images.
    var assets: [ConversionAsset] = []

    /// The parsed document, or `nil` while parsing is under way.
    ///
    /// Parsing happens once per document and off the main thread, so a large
    /// conversion does not stall the interface each time the view refreshes.
    @State private var blocks: [MarkdownBlock]?

    var body: some View {
        Group {
            if let blocks {
                // Lazy, so only the blocks on screen are built.
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        view(for: block)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .task(id: markdown) {
            let source = markdown
            blocks = await Task.detached(priority: .userInitiated) {
                MarkdownParser.parse(source)
            }.value
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(Self.font(forHeadingLevel: level))
                .padding(.top, level <= 2 ? 8 : 2)

        case .paragraph(let text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)

        case .list(let items, let ordered):
            listView(items: items, ordered: ordered)

        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)

        case .code(let text, _):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 3)
                Text(Self.inline(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .image(let alt, let path):
            MarkdownImageView(alt: alt, path: path, assets: assets)

        case .thematicBreak:
            Divider()
        }
    }

    private func listView(items: [MarkdownBlock.Item], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(Self.inline(item.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
            }
        }
    }

    private static func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title.bold()
        case 3: .title2.bold()
        case 4: .title3.bold()
        case 5: .headline
        default: .subheadline.bold()
        }
    }

    /// Resolves the inline Markdown within a single block.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}

/// Draws a Markdown table as a grid.
///
/// Converted tables are often too wide for the window, so the grid scrolls
/// horizontally. Every width is stated explicitly: a divider inside a
/// horizontally scrolling view would otherwise claim unlimited width, leaving
/// the grid without a definite size and its cells drawn over one another.
private struct TableBlockView: View {

    let headers: [String]
    let rows: [[String]]

    /// The most rows drawn. Laying out every cell of a spreadsheet with
    /// thousands of rows takes seconds; the Markdown view shows them all.
    static let maximumRows = 200

    private var visibleRows: [[String]] {
        Array(rows.prefix(Self.maximumRows))
    }

    /// The width given to each column.
    private let columnWidth: CGFloat = 190
    private let spacing: CGFloat = 14

    private var columnCount: Int { max(headers.count, 1) }

    private var contentWidth: CGFloat {
        CGFloat(columnCount) * columnWidth + CGFloat(columnCount - 1) * spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            grid

            if rows.count > Self.maximumRows {
                Text("Showing the first \(Self.maximumRows) of \(rows.count) rows. "
                    + "Switch to Markdown to see them all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var grid: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }

                rule(opacity: 1)

                ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, text in
                            cell(text, isHeader: false)
                        }
                    }

                    if index < visibleRows.count - 1 {
                        rule(opacity: 0.35)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .topLeading)
            .padding(12)
        }
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 8))
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(MarkdownDocumentView.inline(text))
            .font(isHeader ? .headline : .body)
            .frame(width: columnWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A horizontal rule spanning every column.
    private func rule(opacity: Double) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: contentWidth, height: 1)
            .opacity(opacity)
            .gridCellColumns(columnCount)
    }
}

#Preview {
    ScrollView {
        MarkdownDocumentView(markdown: """
            # Report

            Intro text with **bold** and `code`.

            | Key | Summary | Status |
            | --- | --- | --- |
            | AB-1 | First issue | Open |
            | AB-2 | Second issue | Closed |

            - First point
            - Second point

            1. Step one
            2. Step two
            """)
        .padding()
    }
}
