import SwiftUI

/// The empty state shown when no documents have been queued.
struct DropZoneView: View {

    /// Invoked when the user asks to browse for documents.
    var onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Drop Documents Here")
                    .font(.headline)

                Text("PDF documents are converted to Markdown. Word and Excel support is coming.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Choose Documents…", action: onBrowse)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop documents here to convert them")
    }
}

#Preview {
    DropZoneView {}
        .frame(width: 280, height: 400)
}
