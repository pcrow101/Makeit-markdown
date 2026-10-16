import Foundation
import UniformTypeIdentifiers

/// Converts Word documents into Markdown.
///
/// - Note: Registered but not yet implemented. The converter is present so that
///   Word documents are offered in file pickers and produce an explanatory
///   error instead of a generic "unsupported format" message. The shipping
///   implementation will read the Open XML package directly.
public struct DOCXConverter: DocumentConverter {

    public let formatName = "Word"

    public var supportedTypes: [UTType] {
        [
            UTType(importedAs: "org.openxmlformats.wordprocessingml.document"),
            UTType(importedAs: "com.microsoft.word.doc")
        ]
    }

    public init() {}

    public func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        throw ConversionError.notYetImplemented(format: formatName)
    }
}
