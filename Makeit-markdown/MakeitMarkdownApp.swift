import SwiftUI

/// Notifications used to route menu commands to the active window.
///
/// Menu commands live outside the window's view hierarchy, so the command
/// definitions post an intent that ``ContentView`` acts on.
extension Notification.Name {
    static let openDocumentsRequested = Notification.Name("openDocumentsRequested")
    static let saveMarkdownRequested = Notification.Name("saveMarkdownRequested")
}

@main
struct MakeitMarkdownApp: App {

    @State private var settings = ConversionSettings()
    @State private var viewModel: ConversionViewModel

    @Environment(\.openWindow)
    private var openWindow

    init() {
        let settings = ConversionSettings()
        _settings = State(initialValue: settings)
        _viewModel = State(initialValue: ConversionViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(settings)
                .frame(minWidth: 720, minHeight: 440)
        }
        .commands { menuCommands }

        Window("Makeit-Markdown Help", id: WindowID.help) {
            HelpView()
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }

    /// Identifiers for the app's auxiliary windows.
    enum WindowID {
        static let help = "help"
    }

    @CommandsBuilder private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                NotificationCenter.default.post(name: .openDocumentsRequested, object: nil)
            }
            .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Markdown…") {
                NotificationCenter.default.post(name: .saveMarkdownRequested, object: nil)
            }
            .keyboardShortcut("s")
            .disabled(viewModel.convertedJobs.isEmpty)
        }

        CommandGroup(replacing: .help) {
            Button("Makeit-Markdown Help") {
                openHelpWindow()
            }
            .keyboardShortcut("?")
        }
    }

    private func openHelpWindow() {
        openWindow(id: WindowID.help)
    }
}
