import Foundation
import UniformTypeIdentifiers

/// Resolves the converter responsible for a given document.
///
/// The registry is the single entry point shared by the app and the command
/// line tool, so both front ends support exactly the same set of formats and
/// report the same diagnostics.
public struct ConverterRegistry: Sendable {

    private let converters: [any DocumentConverter]

    /// Creates a registry backed by the supplied converters, in priority order.
    public init(converters: [any DocumentConverter]) {
        self.converters = converters
    }

    /// A registry containing every converter that ships with this release.
    ///
    /// Converters for formats that have not shipped yet are included so that
    /// they are advertised in file pickers and produce an explanatory error
    /// rather than a generic "unsupported format" message.
    public static let standard = ConverterRegistry(converters: [
        PDFConverter(),
        DOCXConverter(),
        XLSXConverter()
    ])

    /// Every converter in the registry.
    public var allConverters: [any DocumentConverter] { converters }

    /// The document types accepted by any converter in the registry.
    public var supportedTypes: [UTType] {
        converters.flatMap(\.supportedTypes)
    }

    /// The file extensions accepted by any converter in the registry.
    public var supportedFileExtensions: [String] {
        converters.flatMap(\.supportedFileExtensions)
    }

    /// Returns the converter registered for `type`, if any.
    public func converter(for type: UTType) -> (any DocumentConverter)? {
        converters.first { $0.accepts(type) }
    }

    /// Returns the converter registered for the document at `url`.
    ///
    /// Resolution prefers the type recorded by the file system and falls back to
    /// the path extension, which keeps the command line tool working for files
    /// that carry no extended attributes.
    public func converter(for url: URL) -> (any DocumentConverter)? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let match = converter(for: type) {
            return match
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return converter(for: type)
        }
        return nil
    }

    /// Converts the document at `url` using the registered converter.
    ///
    /// - Throws: ``ConversionError/fileNotFound(url:)`` when the file is
    ///   missing, ``ConversionError/unsupportedFormat(fileExtension:)`` when no
    ///   converter claims the document, or any error raised by the converter.
    public func convert(
        url: URL,
        options: ConversionOptions = .default
    ) async throws -> ConversionResult {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ConversionError.fileNotFound(url: url)
        }
        guard let converter = converter(for: url) else {
            throw ConversionError.unsupportedFormat(fileExtension: url.pathExtension.lowercased())
        }
        return try await converter.convert(url: url, options: options)
    }
}
