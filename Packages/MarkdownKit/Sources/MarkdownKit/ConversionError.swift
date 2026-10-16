import Foundation
import UniformTypeIdentifiers

/// Errors raised while locating, reading, or converting a document.
public enum ConversionError: Error, Equatable, Sendable {

    /// No converter is registered for the supplied document type.
    case unsupportedFormat(fileExtension: String)

    /// A converter is registered but its implementation has not yet shipped.
    case notYetImplemented(format: String)

    /// The file does not exist at the supplied location.
    case fileNotFound(url: URL)

    /// The file exists but could not be read or parsed as the expected format.
    case unreadableDocument(url: URL, reason: String)

    /// The document is encrypted and requires a password that was not supplied.
    case passwordProtected(url: URL)

    /// The document contained no extractable text content.
    case noExtractableText(url: URL)

    /// The destination could not be written.
    case outputWriteFailed(url: URL, reason: String)

    /// The operation was cancelled before it completed.
    case cancelled
}

extension ConversionError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            let suffix = fileExtension.isEmpty ? "files without an extension" : ".\(fileExtension) files"
            return "Makeit-Markdown cannot convert \(suffix)."
        case .notYetImplemented(let format):
            return "\(format) conversion is not available yet."
        case .fileNotFound(let url):
            return "The file “\(url.lastPathComponent)” could not be found."
        case .unreadableDocument(let url, let reason):
            return "The file “\(url.lastPathComponent)” could not be read: \(reason)"
        case .passwordProtected(let url):
            return "The file “\(url.lastPathComponent)” is password protected."
        case .noExtractableText(let url):
            return "No text could be extracted from “\(url.lastPathComponent)”."
        case .outputWriteFailed(let url, let reason):
            return "Could not write to “\(url.lastPathComponent)”: \(reason)"
        case .cancelled:
            return "The conversion was cancelled."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedFormat:
            return "Choose a PDF document. Word and Excel support is planned for a future release."
        case .notYetImplemented:
            return "This format is planned for a future release. Convert a PDF in the meantime."
        case .fileNotFound:
            return "Check that the file still exists and that you have permission to read it."
        case .unreadableDocument:
            return "The file may be damaged. Try opening it in its original application and re-saving it."
        case .passwordProtected:
            return "Remove the password from the document and try again."
        case .noExtractableText:
            return "The document may contain only scanned images. Makeit-Markdown does not perform OCR."
        case .outputWriteFailed:
            return "Choose a different destination folder, or check that you have permission to write there."
        case .cancelled:
            return nil
        }
    }
}
