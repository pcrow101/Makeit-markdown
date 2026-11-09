import Foundation

/// What a paragraph style says about the paragraphs that use it.
struct DOCXStyle {
    var name = ""
    var basedOn: String?
    var outlineLevel: Int?
    var numberingID: String?
    var numberingLevel: Int?
}

/// The paragraph styles of a document, with inheritance resolved on demand.
struct DOCXStyleSheet {

    /// The role a paragraph style gives its paragraphs.
    enum Role: Equatable {
        case body
        case heading(Int)
        case code
        case quote
    }

    var styles: [String: DOCXStyle] = [:]

    /// The role of paragraphs using `styleID`, following `basedOn` links.
    func role(of styleID: String?) -> Role {
        for style in chain(from: styleID) {
            let name = style.name.lowercased()
            if let level = Self.headingLevel(named: name) { return .heading(level) }
            if let outline = style.outlineLevel, (0...8).contains(outline) { return .heading(outline + 1) }
            if name.contains("code") || name.contains("preformatted") || name == "plain text" {
                return .code
            }
            if name == "quote" || name == "intense quote" || name == "block text" { return .quote }
        }
        return .body
    }

    /// The list numbering a style applies, as a numbering ID and level.
    func numbering(of styleID: String?) -> (id: String, level: Int)? {
        for style in chain(from: styleID) {
            if let identifier = style.numberingID {
                return (identifier, style.numberingLevel ?? 0)
            }
        }
        return nil
    }

    private func chain(from styleID: String?) -> [DOCXStyle] {
        var result: [DOCXStyle] = []
        var next = styleID
        // The depth limit guards against a style that is based on itself.
        while let identifier = next, let style = styles[identifier], result.count < 16 {
            result.append(style)
            next = style.basedOn
        }
        return result
    }

    private static func headingLevel(named name: String) -> Int? {
        if name == "title" { return 1 }
        guard name.hasPrefix("heading "),
              let level = Int(name.dropFirst("heading ".count)) else { return nil }
        return (1...9).contains(level) ? level : nil
    }
}

/// Reads the paragraph styles from `word/styles.xml`.
final class DOCXStylesParser: NSObject, XMLParserDelegate {

    private(set) var sheet = DOCXStyleSheet()

    private var currentID: String?
    private var current = DOCXStyle()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let value = XLSXXML.attribute("val", in: attributeDict)
        switch elementName {
        case "w:style":
            let isParagraph = XLSXXML.attribute("type", in: attributeDict) == "paragraph"
            currentID = isParagraph ? XLSXXML.attribute("styleId", in: attributeDict) : nil
            current = DOCXStyle()
        case "w:name":
            current.name = value ?? ""
        case "w:basedOn":
            current.basedOn = value
        case "w:outlineLvl":
            current.outlineLevel = value.flatMap(Int.init)
        case "w:numId":
            current.numberingID = value
        case "w:ilvl":
            current.numberingLevel = value.flatMap(Int.init)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "w:style" else { return }
        if let currentID {
            sheet.styles[currentID] = current
        }
        currentID = nil
    }
}

/// The list definitions from `word/numbering.xml`.
struct DOCXNumbering {

    /// Abstract definition ID for each numbering ID.
    var abstractIDs: [String: String] = [:]

    /// Number format for each level of each abstract definition.
    var formats: [String: [Int: String]] = [:]

    /// Whether level `level` of list `numberingID` is numbered rather than
    /// bulleted.
    func isOrdered(_ numberingID: String, level: Int) -> Bool {
        guard let abstractID = abstractIDs[numberingID],
              let format = formats[abstractID]?[level] else { return false }
        return format != "bullet" && format != "none"
    }

    /// Whether `numberingID` refers to a list. Word uses ID 0 to remove the
    /// numbering a style would otherwise apply.
    func isList(_ numberingID: String) -> Bool {
        numberingID != "0" && abstractIDs[numberingID] != nil
    }
}

/// Reads `word/numbering.xml`.
final class DOCXNumberingParser: NSObject, XMLParserDelegate {

    private(set) var numbering = DOCXNumbering()

    private var abstractID: String?
    private var level: Int?
    private var numberingID: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "w:abstractNum":
            abstractID = XLSXXML.attribute("abstractNumId", in: attributeDict)
        case "w:lvl" where abstractID != nil:
            level = XLSXXML.attribute("ilvl", in: attributeDict).flatMap(Int.init)
        case "w:numFmt":
            if let abstractID, let level, let format = XLSXXML.attribute("val", in: attributeDict) {
                numbering.formats[abstractID, default: [:]][level] = format
            }
        case "w:num":
            numberingID = XLSXXML.attribute("numId", in: attributeDict)
        case "w:abstractNumId":
            if let numberingID, let value = XLSXXML.attribute("val", in: attributeDict) {
                numbering.abstractIDs[numberingID] = value
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "w:abstractNum": abstractID = nil
        case "w:lvl": level = nil
        case "w:num": numberingID = nil
        default: break
        }
    }
}
