import Foundation
import MarkdownKit

/// The progress of a single document through the conversion pipeline.
enum JobStatus: Equatable, Sendable {

    /// Queued, but conversion has not begun.
    case waiting

    /// Conversion is in progress.
    case converting

    /// Conversion finished and Markdown is available.
    case converted

    /// Conversion failed with the given user facing message.
    case failed(String)

    /// Indicates whether the job still needs to be converted.
    ///
    /// Failed jobs are included so that a retry picks them up after the user
    /// has corrected the underlying problem.
    var isPending: Bool {
        switch self {
        case .waiting, .failed: return true
        case .converting, .converted: return false
        }
    }

    /// A short description suitable for a list row.
    var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .converting: return "Converting…"
        case .converted: return "Converted"
        case .failed: return "Failed"
        }
    }
}

/// One document queued for conversion, together with its outcome.
struct ConversionJob: Identifiable, Equatable, Sendable {

    let id: UUID
    let sourceURL: URL
    var status: JobStatus
    var result: ConversionResult?

    init(sourceURL: URL, id: UUID = UUID(), status: JobStatus = .waiting) {
        self.id = id
        self.sourceURL = sourceURL
        self.status = status
    }

    /// The file name shown in the job list.
    var displayName: String { sourceURL.lastPathComponent }

    /// The generated Markdown, once conversion has succeeded.
    var markdown: String? { result?.markdown }

    /// Non-fatal issues reported by the converter.
    var warnings: [ConversionWarning] { result?.warnings ?? [] }

    /// The file name proposed when saving this job's Markdown.
    var suggestedFileName: String {
        result?.suggestedFileName
            ?? sourceURL.deletingPathExtension().lastPathComponent + ".md"
    }
}
