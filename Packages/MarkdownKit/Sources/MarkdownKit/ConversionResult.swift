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

    public init(
        markdown: String,
        sourceURL: URL,
        pageCount: Int? = nil,
        warnings: [ConversionWarning] = []
    ) {
        self.markdown = markdown
        self.sourceURL = sourceURL
        self.pageCount = pageCount
        self.warnings = warnings
    }

    /// A conventional output file name derived from the source document.
    public var suggestedFileName: String {
        sourceURL.deletingPathExtension().lastPathComponent + ".md"
    }
}
