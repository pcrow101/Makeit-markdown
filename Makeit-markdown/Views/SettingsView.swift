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

                Toggle("Reconstruct tables", isOn: $settings.extractTables)
                    .help("Rebuild tables as Markdown tables. Turn off to keep table text as plain lines.")
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
                Toggle(
                    "Extract pictures, drawings and charts",
                    isOn: $settings.extractGraphics
                )
                .help(
                    """
                    Saves each image to an _images folder beside the Markdown file. \
                    Turn off to produce no images and no image links.
                    """
                )
            } header: {
                Text("Images")
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
