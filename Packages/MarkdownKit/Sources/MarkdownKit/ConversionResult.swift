import Foundation

/// A non-fatal condition encountered while converting a document.
public struct ConversionWarning: Sendable, Equatable, Codable {

    /// Machine readable classification of the warning.
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The document yielded no extractable text on one or more pages.
        case emptyPage
        /// The document appears to contain scanned images rather than text.
        case imageOnlyContent
        /// The document is encrypted but was readable with an empty password.
        case encryptedDocument
        /// Experimental table extraction produced a low confidence result.
        case experimentalTableHeuristic
        /// A feature of the source document could not be represented.
        case unsupportedFeature
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// A file referenced by the generated Markdown, such as an extracted image.
public struct ConversionAsset: Sendable, Equatable {

    /// Path relative to the directory containing the Markdown file.
    public let relativePath: String

    public let data: Data

    public init(relativePath: String, data: Data) {
        self.relativePath = relativePath
        self.data = data
    }

    /// Writes the asset beneath `directory`, creating folders as needed.
    public func write(relativeTo directory: URL) throws {
        let destination = directory.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }
}

/// The product of a successful document conversion.
public struct ConversionResult: Sendable, Equatable {

    /// The generated Markdown document.
    public let markdown: String

    /// The location of the document that produced `markdown`.
    public let sourceURL: URL

    /// The number of pages processed, when the source format is paginated.
    public let pageCount: Int?

    /// Non-fatal issues encountered during conversion.
    public let warnings: [ConversionWarning]

    /// Files referenced by `markdown`, which must be saved beside it.
    public let assets: [ConversionAsset]

    public init(
        markdown: String,
        sourceURL: URL,
        pageCount: Int? = nil,
        warnings: [ConversionWarning] = [],
        assets: [ConversionAsset] = []
    ) {
        self.markdown = markdown
        self.sourceURL = sourceURL
        self.pageCount = pageCount
        self.warnings = warnings
        self.assets = assets
    }

    /// A conventional output file name derived from the source document.
    public var suggestedFileName: String {
        sourceURL.deletingPathExtension().lastPathComponent + ".md"
    }
}
