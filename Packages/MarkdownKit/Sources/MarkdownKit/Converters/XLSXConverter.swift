import Foundation
import UniformTypeIdentifiers

/// Converts Excel workbooks into Markdown tables.
///
/// - Note: Registered but not yet implemented. The converter is present so that
///   workbooks are offered in file pickers and produce an explanatory error
///   instead of a generic "unsupported format" message. The shipping
///   implementation will read the Open XML package directly and emit one
///   Markdown table per worksheet.
public struct XLSXConverter: DocumentConverter {

    public let formatName = "Excel"

    public var supportedTypes: [UTType] {
        [
            UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet"),
            UTType(importedAs: "com.microsoft.excel.xls")
        ]
    }

    public init() {}

    public func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        throw ConversionError.notYetImplemented(format: formatName)
    }
}
