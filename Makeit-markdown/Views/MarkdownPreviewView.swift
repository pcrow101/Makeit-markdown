import MarkdownKit
import SwiftUI

/// Shows the Markdown produced for a single document.
struct MarkdownPreviewView: View {

    let job: ConversionJob

    /// Whether to show the raw Markdown source or its rendered form.
    @State private var mode: PreviewMode = .source

    enum PreviewMode: String, CaseIterable, Identifiable {
        case source = "Markdown"
        case rendered = "Preview"

        var id: Self { self }
    }

    var body: some View {
        Group {
            switch job.status {
            case .converted:
                converted
            case .failed(let message):
                ContentUnavailableView {
                    Label("Conversion Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            case .converting:
                ProgressView("Converting \(job.displayName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .waiting:
                ContentUnavailableView {
                    Label("Not Converted Yet", systemImage: "clock")
                } description: {
                    Text("Choose Convert to generate Markdown for this document.")
                }
            }
        }
        .navigationTitle(job.displayName)
        .navigationSubtitle(job.status.label)
    }

    @ViewBuilder private var converted: some View {
        VStack(spacing: 0) {
            if !job.warnings.isEmpty {
                warningBanner
            }

            switch mode {
            case .source:
                ScrollView {
                    Text(job.markdown ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            case .rendered:
                ScrollView {
                    MarkdownDocumentView(markdown: job.markdown ?? "", assets: job.result?.assets ?? [])
                        .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem {
                Button("Copy", systemImage: "doc.on.doc") {
                    copyToPasteboard()
                }
                .help("Copy the Markdown to the clipboard")
            }
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(job.warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func copyToPasteboard() {
        guard let markdown = job.markdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}

#Preview {
    var job = ConversionJob(sourceURL: URL(filePath: "/tmp/report.pdf"), status: .converted)
    job.result = ConversionResult(
        markdown: "# Report\n\nSome body text.\n",
        sourceURL: URL(filePath: "/tmp/report.pdf"),
        pageCount: 1
    )
    return MarkdownPreviewView(job: job)
}
