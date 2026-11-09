import Foundation

/// A failure while reading the parts of an Open XML workbook.
enum XLSXError: Error, Equatable {
    /// The archive is not a spreadsheet workbook.
    case notAWorkbook
    /// A part of the workbook is not well formed XML.
    case malformedXML(part: String)
}

/// Runs an `XMLParser` over one part of a workbook.
enum XLSXXML {

    static func parse(_ data: Data, with delegate: XMLParserDelegate, part: String) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw XLSXError.malformedXML(part: part) }
    }

    /// The value of the attribute whose name is `local`, with or without a
    /// namespace prefix such as `r:id`.
    static func attribute(_ local: String, in attributes: [String: String]) -> String? {
        if let exact = attributes[local] { return exact }
        return attributes.first { $0.key.hasSuffix(":" + local) }?.value
    }
}

/// A sheet listed in `xl/workbook.xml`.
struct XLSXSheetReference {
    let name: String
    let relationshipID: String
    let isHidden: Bool
}

/// Reads the sheet list and date system from `xl/workbook.xml`.
final class XLSXWorkbookParser: NSObject, XMLParserDelegate {

    private(set) var sheets: [XLSXSheetReference] = []
    private(set) var uses1904Dates = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "sheet":
            guard let name = attributeDict["name"],
                  let relationship = XLSXXML.attribute("id", in: attributeDict) else { return }
            let state = attributeDict["state"] ?? "visible"
            sheets.append(XLSXSheetReference(
                name: name,
                relationshipID: relationship,
                isHidden: state != "visible"
            ))
        case "workbookPr":
            let flag = attributeDict["date1904"]?.lowercased()
            uses1904Dates = flag == "1" || flag == "true"
        default:
            break
        }
    }
}

/// A relationship listed in a `.rels` part.
struct XLSXRelationship {
    let identifier: String
    let type: String
    let target: String
}

/// Reads a `.rels` part.
final class XLSXRelationshipsParser: NSObject, XMLParserDelegate {

    private(set) var relationships: [XLSXRelationship] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Relationship",
              let identifier = attributeDict["Id"],
              let target = attributeDict["Target"] else { return }
        relationships.append(XLSXRelationship(
            identifier: identifier,
            type: attributeDict["Type"] ?? "",
            target: target
        ))
    }
}

/// Reads `xl/sharedStrings.xml`.
///
/// Rich text is flattened to its plain text, and phonetic guides, which repeat
/// the text in another script, are left out.
final class XLSXSharedStringsParser: NSObject, XMLParserDelegate {

    private(set) var strings: [String] = []

    private var current = ""
    private var isInsideText = false
    private var isInsidePhonetic = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "si": current = ""
        case "rPh": isInsidePhonetic = true
        case "t": isInsideText = !isInsidePhonetic
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideText { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "t": isInsideText = false
        case "rPh": isInsidePhonetic = false
        case "si": strings.append(current)
        default: break
        }
    }
}

/// Reads the number formats from `xl/styles.xml`.
final class XLSXStylesParser: NSObject, XMLParserDelegate {

    private(set) var styles = XLSXStyles()

    private var isInsideCellFormats = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "numFmt":
            if let identifier = attributeDict["numFmtId"].flatMap(Int.init),
               let code = attributeDict["formatCode"] {
                styles.customFormats[identifier] = code
            }
        case "cellXfs":
            isInsideCellFormats = true
        case "xf" where isInsideCellFormats:
            styles.cellFormatIDs.append(attributeDict["numFmtId"].flatMap(Int.init) ?? 0)
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
        if elementName == "cellXfs" { isInsideCellFormats = false }
    }
}
