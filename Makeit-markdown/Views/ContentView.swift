import MarkdownKit
import SwiftUI
import UniformTypeIdentifiers

/// The main window: a queue of documents beside a preview of their Markdown.
struct ContentView: View {

    @Environment(ConversionViewModel.self)
    private var viewModel

    @State private var isImportingFiles = false
    @State private var isChoosingSaveDirectory = false
    @State private var isTargetedForDrop = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isTargetedForDrop = $0 }
        .overlay {
            if isTargetedForDrop {
                DropIndicatorView()
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: viewModel.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fileImporter(
            isPresented: $isChoosingSaveDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            handleSaveDirectory(result)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocumentsRequested)) { _ in
            isImportingFiles = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveMarkdownRequested)) { _ in
            beginSave()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder private var sidebar: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.jobs.isEmpty {
                DropZoneView { isImportingFiles = true }
            } else {
                List(selection: $viewModel.selection) {
                    ForEach(viewModel.jobs) { job in
                        JobRowView(job: job).tag(job.id)
                    }
                }
                .listStyle(.sidebar)
                .contextMenu(forSelectionType: ConversionJob.ID.self) { ids in
                    Button("Remove", role: .destructive) {
                        viewModel.removeJobs(ids: ids)
                    }
                } primaryAction: { _ in }
            }
        }
        .navigationTitle("Documents")
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let job = viewModel.selectedJob {
            MarkdownPreviewView(job: job)
        } else {
            ContentUnavailableView(
                "No Document Selected",
                systemImage: "doc.text",
                description: Text("Choose a document from the list to preview its Markdown.")
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Documents", systemImage: "plus") {
                isImportingFiles = true
            }
            .help("Add documents to the conversion queue")
        }

        ToolbarItem(placement: .primaryAction) {
            if viewModel.isConverting {
                Button("Cancel", systemImage: "stop.fill") {
                    viewModel.cancel()
                }
                .help("Stop converting")
            } else {
                Button("Convert", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.convertAll()
                }
                .disabled(!viewModel.hasPendingJobs)
                .help("Convert every queued document")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Save", systemImage: "square.and.arrow.down") {
                beginSave()
            }
            .disabled(viewModel.convertedJobs.isEmpty)
            .help("Save the converted Markdown to a folder")
        }
    }

    // MARK: - Actions

    private func beginSave() {
        guard !viewModel.convertedJobs.isEmpty else { return }
        isChoosingSaveDirectory = true
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            viewModel.addFiles(urls)
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleSaveDirectory(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let directory):
            viewModel.saveAll(to: directory)
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

/// Highlights the window while a drag is hovering over it.
private struct DropIndicatorView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .padding(8)
            .allowsHitTesting(false)
    }
}

#Preview {
    let settings = ConversionSettings(defaults: .standard)
    return ContentView()
        .environment(ConversionViewModel(settings: settings))
        .environment(settings)
}
