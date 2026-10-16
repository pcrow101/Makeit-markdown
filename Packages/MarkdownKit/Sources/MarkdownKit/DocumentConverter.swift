import Foundation
import UniformTypeIdentifiers

/// A type that converts a single document format into Markdown.
///
/// Conformances must be free of user interface dependencies so that they can be
/// driven equally by the app and by the command line tool.
public protocol DocumentConverter: Sendable {

    /// A human readable name for the format, used in menus and diagnostics.
    var formatName: String { get }

    /// The document types this converter accepts.
    var supportedTypes: [UTType] { get }

    /// Converts the document at `url` into Markdown.
    ///
    /// - Parameters:
    ///   - url: The location of the source document.
    ///   - options: Options controlling the shape of the generated Markdown.
    /// - Returns: The generated Markdown along with any non-fatal warnings.
    /// - Throws: ``ConversionError`` if the document cannot be converted.
    func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult
}

extension DocumentConverter {

    /// Indicates whether this converter claims the supplied document type.
    public func accepts(_ type: UTType) -> Bool {
        supportedTypes.contains { type.conforms(to: $0) }
    }

    /// The file extensions this converter claims, for display purposes.
    public var supportedFileExtensions: [String] {
        supportedTypes.flatMap { $0.tags[.filenameExtension] ?? [] }
    }
}
