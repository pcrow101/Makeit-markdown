import Foundation
import Testing
@testable import Makeit_markdown
import MarkdownKit
import UniformTypeIdentifiers

/// A converter that returns a scripted outcome, so view model behaviour can be
/// tested without touching the file system or PDFKit.
private struct StubConverter: DocumentConverter {

    enum Outcome: Sendable {
        case success(markdown: String, warnings: [ConversionWarning])
        case failure(ConversionError)
        case hang
    }

    let formatName = "Stub"
    var supportedTypes: [UTType] { [.data] }
    let outcome: Outcome
    var assets: [ConversionAsset] = []

    init(_ outcome: Outcome = .success(markdown: "# Stub\n", warnings: [])) {
        self.outcome = outcome
    }

    func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        switch outcome {
        case .success(let markdown, let warnings):
            return ConversionResult(
                markdown: markdown,
                sourceURL: url,
                pageCount: 1,
                warnings: warnings,
                assets: assets
            )

        case .failure(let error):
            throw error

        case .hang:
            // Long enough to observe the converting state, but cancellable.
            try await Task.sleep(for: .seconds(60))
            return ConversionResult(markdown: "", sourceURL: url)
        }
    }
}

@MainActor
@Suite("ConversionViewModel")
struct ConversionViewModelTests {

    /// A temporary directory removed when the test instance is released.
    final class Scratch {
        let directory: URL

        init() {
            directory = URL(filePath: NSTemporaryDirectory())
                .appending(path: "MakeitMarkdownTests-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private let scratch = Scratch()

    /// A settings store backed by a throwaway defaults domain.
    private func makeSettings() -> ConversionSettings {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return ConversionSettings(defaults: defaults)
    }

    private func makeViewModel(_ outcome: StubConverter.Outcome) -> ConversionViewModel {
        ConversionViewModel(
            settings: makeSettings(),
            registry: ConverterRegistry(converters: [StubConverter(outcome)])
        )
    }

    /// Creates an empty file in the scratch directory and returns its location.
    ///
    /// The registry checks that a document exists before dispatching it, so
    /// tests need real files even when the converter itself is a stub.
    private func url(_ name: String) -> URL {
        let url = scratch.directory.appending(path: name)
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data())
        return url
    }

    // MARK: - Queue management

    @Test("A new view model starts with an empty queue")
    func initialState() {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        #expect(viewModel.jobs.isEmpty)
        #expect(viewModel.selection == nil)
        #expect(!viewModel.isConverting)
        #expect(!viewModel.hasPendingJobs)
    }

    @Test("Adding files queues them and selects the first")
    func addFiles() {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        #expect(viewModel.jobs.count == 2)
        #expect(viewModel.selection == viewModel.jobs.first?.id)
        #expect(viewModel.hasPendingJobs)
        #expect(viewModel.jobs.allSatisfy { $0.status == .waiting })
    }

    @Test("Adding the same file twice does not duplicate it")
    func duplicateFilesIgnored() {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf")])
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        #expect(viewModel.jobs.count == 2)
    }

    @Test("Adding files does not move the existing selection")
    func selectionIsPreserved() {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf")])
        let original = viewModel.selection

        viewModel.addFiles([url("b.pdf")])

        #expect(viewModel.selection == original)
    }

    @Test("Removing the selected job moves the selection")
    func removeSelectedJob() throws {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        let selected = try #require(viewModel.selection)
        viewModel.removeJobs(ids: [selected])

        #expect(viewModel.jobs.count == 1)
        #expect(viewModel.selection == viewModel.jobs.first?.id)
    }

    @Test("Clearing the queue removes everything")
    func removeAllJobs() {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        viewModel.removeAllJobs()

        #expect(viewModel.jobs.isEmpty)
        #expect(viewModel.selection == nil)
    }

    // MARK: - Conversion

    @Test("A successful run marks every job converted")
    func successfulConversion() async {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        #expect(viewModel.jobs.allSatisfy { $0.status == .converted })
        #expect(viewModel.jobs.allSatisfy { $0.markdown == "# Stub\n" })
        #expect(viewModel.convertedJobs.count == 2)
        #expect(!viewModel.isConverting)
        #expect(!viewModel.hasPendingJobs)
    }

    @Test("A failing converter records an explanatory message")
    func failedConversion() async throws {
        let viewModel = makeViewModel(.failure(.notYetImplemented(format: "Word")))
        viewModel.addFiles([url("a.docx")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        let job = try #require(viewModel.jobs.first)
        guard case .failed(let message) = job.status else {
            Issue.record("Expected the job to fail, but it was \(job.status).")
            return
        }
        #expect(message.contains("Word"))
        #expect(job.markdown == nil)
    }

    @Test("A failed job is eligible for a retry")
    func failedJobsCanBeRetried() async {
        let viewModel = makeViewModel(.failure(.cancelled))
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        #expect(viewModel.hasPendingJobs)
    }

    @Test("Warnings from the converter are carried through to the job")
    func warningsArePreserved() async throws {
        let warning = ConversionWarning(kind: .emptyPage, message: "Page 2 was empty.")
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: [warning]))
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        let job = try #require(viewModel.jobs.first)
        #expect(job.warnings == [warning])
    }

    @Test("Converting an empty queue does nothing")
    func convertingEmptyQueue() async {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        #expect(!viewModel.isConverting)
        #expect(viewModel.jobs.isEmpty)
    }

    @Test("Jobs are marked as converting while a run is in flight")
    func convertingState() async {
        let viewModel = makeViewModel(.hang)
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()

        #expect(viewModel.isConverting)
        #expect(viewModel.jobs.allSatisfy { $0.status == .converting })

        viewModel.cancel()
    }

    @Test("Cancelling returns in-flight jobs to the queue")
    func cancellation() async {
        let viewModel = makeViewModel(.hang)
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()
        viewModel.cancel()

        #expect(!viewModel.isConverting)
        #expect(viewModel.jobs.allSatisfy { $0.status == .waiting })
        #expect(viewModel.hasPendingJobs)
    }

    @Test("A second run is ignored while one is already in progress")
    func concurrentRunsAreIgnored() async {
        let viewModel = makeViewModel(.hang)
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()
        viewModel.convertAll()

        #expect(viewModel.isConverting)
        viewModel.cancel()
    }

    // MARK: - Saving

    @Test("Saving writes one Markdown file per converted document")
    func saveAll() async throws {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf"), url("b.pdf")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "makeit-markdown-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let written = viewModel.saveAll(to: directory)

        #expect(written == 2)
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .sorted()
        #expect(names == ["a.md", "b.md"])
    }

    @Test("Saving writes extracted images into the _images folder")
    func saveAllWritesAssets() async throws {
        let markdown = "![Figure 1](<a_images/page-1-figure-1.png>)\n"
        var converter = StubConverter(.success(markdown: markdown, warnings: []))
        converter.assets = [
            ConversionAsset(relativePath: "a_images/page-1-figure-1.png", data: Data([1, 2, 3]))
        ]
        let viewModel = ConversionViewModel(
            settings: makeSettings(),
            registry: ConverterRegistry(converters: [converter])
        )
        viewModel.addFiles([url("a.pdf")])

        viewModel.convertAll()
        await viewModel.waitForConversionToFinish()

        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "makeit-markdown-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(viewModel.saveAll(to: directory) == 1)
        let image = directory.appending(path: "a_images/page-1-figure-1.png")
        #expect(try Data(contentsOf: image) == Data([1, 2, 3]))
    }

    @Test("Saving an unconverted queue writes nothing")
    func saveWithoutConversion() throws {
        let viewModel = makeViewModel(.success(markdown: "# Stub\n", warnings: []))
        viewModel.addFiles([url("a.pdf")])

        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "makeit-markdown-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(viewModel.saveAll(to: directory) == 0)
    }
}
