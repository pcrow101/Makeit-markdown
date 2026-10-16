import SwiftUI

/// The conversion preferences pane.
struct SettingsView: View {

    @Environment(ConversionSettings.self)
    private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Detect headings", isOn: $settings.detectHeadings)
                    .help("Infer Markdown headings from type size and weight.")

                Toggle("Detect lists", isOn: $settings.detectLists)
                    .help("Infer bulleted and numbered lists from line prefixes.")
            } header: {
                Text("Structure")
            }

            Section {
                Toggle("Separate pages with a horizontal rule", isOn: $settings.insertPageBreaks)

                Toggle("Collapse blank lines", isOn: $settings.normalizeWhitespace)
                    .help("Keeps the output compact, which suits language models.")

                Toggle(
                    "Remove repeated headers and footers",
                    isOn: $settings.stripRepeatedPageFurniture
                )
                .help("Drops banners and page numbers that repeat on most pages.")
            } header: {
                Text("Layout")
            }

            Section {
                Toggle("Reconstruct tables", isOn: $settings.experimentalTableExtraction)

                Text(
                    """
                    Experimental. Recovering tables from a PDF's positioned text \
                    is unreliable, so check any tables against the original document.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Experimental")
            }

            Section {
                Button("Restore Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
        .environment(ConversionSettings(defaults: .standard))
}
