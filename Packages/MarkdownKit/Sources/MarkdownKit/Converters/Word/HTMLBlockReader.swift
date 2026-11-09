import Foundation

/// Reads the structure of an HTML document into document blocks.
///
/// Word can save documents as HTML with a `.doc` extension, and Confluence
/// exports pages to Word the same way, so `.doc` files are often HTML. The
/// reader handles headings, paragraphs, nested lists, tables, preformatted
/// text, quotations and pictures. Inline formatting is dropped.
///
/// Pictures are reported as `.image` blocks whose path is the `src` attribute,
/// for the caller to resolve.
struct HTMLBlockReader {

    private enum Context {
        case heading(Int)
        case item(indent: Int, ordered: Bool)
        case preformatted
        case quote

        /// The case, ignoring associated values.
        var kind: Int {
            switch self {
            case .heading: return 0
            case .item: return 1
            case .preformatted: return 2
            case .quote: return 3
            }
        }
    }

    private struct Table {
        var rows: [[String]] = []
        var row: [String]?
        var cell: [String]?
        var span = 1
        var images: [DocumentBlock] = []
    }

    private static let blockElements: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "nav", "aside", "main", "center",
        "address", "figure", "figcaption", "form", "fieldset", "dl", "dt", "dd", "caption",
        "details", "summary", "tbody", "thead", "tfoot", "hr", "body", "html"
    ]

    private var blocks: [DocumentBlock] = []
    private var contexts: [Context] = []
    private var lists: [Bool] = []
    private var tables: [Table] = []
    private var buffer = ""
    private var headDepth = 0

    /// The blocks of `html`, in reading order.
    static func blocks(from html: String) -> [DocumentBlock] {
        var reader = HTMLBlockReader()
        for token in HTMLTokenizer.tokens(in: html) {
            reader.consume(token)
        }
        reader.flush()
        while !reader.tables.isEmpty {
            reader.endTable()
        }
        return reader.blocks
    }

    private var isPreformatted: Bool {
        contexts.contains { if case .preformatted = $0 { return true }; return false }
    }

    // MARK: - Tokens

    private mutating func consume(_ token: HTMLToken) {
        switch token {
        case .text(let text):
            guard headDepth == 0 else { return }
            if isPreformatted {
                buffer += text.replacingOccurrences(of: "\r\n", with: "\n")
            } else {
                buffer += text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
        case .start(let name, let attributes):
            start(name, attributes: attributes)
        case .end(let name):
            end(name)
        }
    }

    private mutating func start(_ name: String, attributes: [String: String]) {
        if name == "head" { headDepth += 1 }
        if name == "br" {
            buffer += "\n"
            return
        }
        guard Self.structural(name) else { return }
        flush()

        if let context = Self.context(for: name) {
            contexts.append(context)
            return
        }

        switch name {
        case "ul", "ol":
            lists.append(name == "ol")
        case "li":
            if case .item? = contexts.last { contexts.removeLast() }
            contexts.append(.item(indent: max(lists.count - 1, 0), ordered: lists.last ?? false))
        case "img":
            addImage(source: attributes["src"], altText: attributes["alt"] ?? attributes["title"] ?? "")
        default:
            startTablePart(name, attributes: attributes)
        }
    }

    private mutating func end(_ name: String) {
        if name == "head" { headDepth = max(headDepth - 1, 0) }
        guard Self.structural(name) else { return }
        flush()

        if let context = Self.context(for: name) {
            popContext { $0.kind == context.kind }
            return
        }

        switch name {
        case "li":
            popContext { if case .item = $0 { return true }; return false }
        case "ul", "ol":
            if case .item? = contexts.last { contexts.removeLast() }
            _ = lists.popLast()
        default:
            endTablePart(name)
        }
    }

    /// The context opened by headings, preformatted text and quotations.
    private static func context(for name: String) -> Context? {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6": return .heading(Int(String(name.dropFirst())) ?? 1)
        case "pre": return .preformatted
        case "blockquote": return .quote
        default: return nil
        }
    }

    private mutating func startTablePart(_ name: String, attributes: [String: String]) {
        switch name {
        case "table":
            tables.append(Table())
        case "tr":
            endCell()
            endRow()
            if !tables.isEmpty { tables[tables.count - 1].row = [] }
        case "td", "th":
            startCell(span: attributes["colspan"].flatMap(Int.init) ?? 1)
        default:
            break
        }
    }

    private mutating func endTablePart(_ name: String) {
        switch name {
        case "td", "th":
            endCell()
        case "tr":
            endCell()
            endRow()
        case "table":
            endTable()
        default:
            break
        }
    }

    private static func structural(_ name: String) -> Bool {
        blockElements.contains(name) || [
            "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "pre", "blockquote",
            "table", "tr", "td", "th", "img"
        ].contains(name)
    }

    /// Removes the innermost context matching `isMatch` and any inside it.
    private mutating func popContext(where isMatch: (Context) -> Bool) {
        guard let index = contexts.lastIndex(where: isMatch) else { return }
        contexts.removeSubrange(index...)
    }

    // MARK: - Text

    /// Emits the buffered text as a block suited to where it appears.
    private mutating func flush() {
        let raw = buffer
        buffer = ""

        let text = isPreformatted
            ? raw.trimmingCharacters(in: .newlines)
            : WordBlockAdjuster.singleLine(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if !tables.isEmpty, tables[tables.count - 1].cell != nil {
            tables[tables.count - 1].cell?.append(WordBlockAdjuster.singleLine(text))
            return
        }

        switch contexts.last {
        case .heading(let level)?:
            blocks.append(.heading(text: text, level: level))
        case .item(let indent, let ordered)?:
            blocks.append(.listItem(text: text, ordered: ordered, indentLevel: indent))
        case .preformatted?:
            blocks.append(.codeBlock(text: text))
        case .quote?:
            blocks.append(.blockQuote(text: text))
        case nil:
            blocks.append(.paragraph(text: text))
        }
    }

    private mutating func addImage(source: String?, altText: String) {
        guard let source, !source.isEmpty else { return }
        let image = DocumentBlock.image(path: source, altText: altText)
        if !tables.isEmpty, tables[tables.count - 1].cell != nil {
            tables[tables.count - 1].images.append(image)
        } else {
            blocks.append(image)
        }
    }

    // MARK: - Tables

    private mutating func startCell(span: Int) {
        guard !tables.isEmpty else { return }
        endCell()
        if tables[tables.count - 1].row == nil { tables[tables.count - 1].row = [] }
        tables[tables.count - 1].cell = []
        tables[tables.count - 1].span = min(max(span, 1), 64)
    }

    private mutating func endCell() {
        guard !tables.isEmpty, let cell = tables[tables.count - 1].cell else { return }
        let span = tables[tables.count - 1].span
        tables[tables.count - 1].row?.append(cell.joined(separator: " "))
        tables[tables.count - 1].row?.append(contentsOf: Array(repeating: "", count: span - 1))
        tables[tables.count - 1].cell = nil
    }

    private mutating func endRow() {
        guard !tables.isEmpty, let row = tables[tables.count - 1].row else { return }
        tables[tables.count - 1].rows.append(row)
        tables[tables.count - 1].row = nil
    }

    private mutating func endTable() {
        endCell()
        endRow()
        guard let table = tables.popLast() else { return }

        // A table nested in a cell is flattened into the outer cell's text.
        if !tables.isEmpty, tables[tables.count - 1].cell != nil {
            let text = table.rows.flatMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            tables[tables.count - 1].cell?.append(text)
            tables[tables.count - 1].images.append(contentsOf: table.images)
            return
        }
        blocks.append(.table(rows: table.rows))
        blocks.append(contentsOf: table.images)
    }
}
