import MarkdownKit
import SwiftUI

/// A single row in the document queue.
struct JobRowView: View {

    let job: ConversionJob

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if !job.warnings.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warningSummary)
                    .accessibilityLabel("\(job.warnings.count) warnings")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView()
                .controlSize(.small)
        case .converted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var subtitle: String {
        switch job.status {
        case .failed(let message):
            return message
        case .converted:
            guard let pages = job.result?.pageCount else { return job.status.label }
            return "Converted · \(pages) page\(pages == 1 ? "" : "s")"
        case .waiting, .converting:
            return job.status.label
        }
    }

    private var warningSummary: String {
        job.warnings.map(\.message).joined(separator: "\n")
    }
}

#Preview {
    List {
        JobRowView(job: ConversionJob(sourceURL: URL(filePath: "/tmp/report.pdf")))
        JobRowView(
            job: ConversionJob(
                sourceURL: URL(filePath: "/tmp/notes.pdf"),
                status: .converting
            )
        )
        JobRowView(
            job: ConversionJob(
                sourceURL: URL(filePath: "/tmp/broken.pdf"),
                status: .failed("The file could not be read.")
            )
        )
    }
}
