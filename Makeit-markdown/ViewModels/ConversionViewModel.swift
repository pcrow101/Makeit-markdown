import Foundation
import MarkdownKit
import Observation
import UniformTypeIdentifiers

/// Drives the conversion queue shown by the main window.
///
/// The view model owns all conversion state and is the only place the app
/// touches ``MarkdownKit``. Views read from it and send intent back to it, so
/// the conversion pipeline can be exercised in tests without any user interface.
@MainActor
@Observable
final class ConversionViewModel {

    // MARK: - State

    /// Every document queued, in the order it was added.
    private(set) var jobs: [ConversionJob] = []

    /// The job currently shown in the detail pane.
    var selection: ConversionJob.ID?

    /// Whether a conversion run is in progress.
    private(set) var isConverting = false

    /// A message describing the most recent non-conversion failure, such as a
    /// problem writing a file.
    var errorMessage: String?

    private let registry: ConverterRegistry
    private let settings: ConversionSettings
    private var conversionTask: Task<Void, Never>?

    init(settings: ConversionSettings, registry: ConverterRegistry = .standard) {
        self.settings = settings
        self.registry = registry
    }

    // MARK: - Derived state

    /// The job matching ``selection``, if any.
    var selectedJob: ConversionJob? {
        guard let selection else { return nil }
        return jobs.first { $0.id == selection }
    }

    /// Whether any job is waiting to be converted or can be retried.
    var hasPendingJobs: Bool {
        jobs.contains { $0.status.isPending }
    }

    /// Every job that has produced Markdown.
    var convertedJobs: [ConversionJob] {
        jobs.filter { $0.status == .converted }
    }

    /// The document types the app can accept.
    var supportedContentTypes: [UTType] {
        registry.supportedTypes
    }

    // MARK: - Queue management

    /// Adds `urls` to the queue, ignoring documents that are already present.
    func addFiles(_ urls: [URL]) {
        let existing = Set(jobs.map(\.sourceURL))
        let additions = urls
            .map(\.standardizedFileURL)
            .filter { !existing.contains($0) }
            .map { ConversionJob(sourceURL: $0) }

        guard !additions.isEmpty else { return }
        jobs.append(contentsOf: additions)
        selection = selection ?? additions.first?.id
    }

    /// Removes the jobs identified by `ids` from the queue.
    func removeJobs(ids: Set<ConversionJob.ID>) {
        jobs.removeAll { ids.contains($0.id) }
        if let selection, ids.contains(selection) {
            self.selection = jobs.first?.id
        }
    }

    /// Empties the queue and cancels any run in progress.
    func removeAllJobs() {
        cancel()
        jobs.removeAll()
        selection = nil
    }

    // MARK: - Conversion

    /// Converts every job that is waiting or previously failed.
    ///
    /// Documents are converted concurrently, bounded by the number of active
    /// processors so that a large queue does not swamp the machine.
    func convertAll() {
        guard !isConverting else { return }

        let pending = jobs.filter { $0.status.isPending }
        guard !pending.isEmpty else { return }

        for job in pending {
            updateStatus(.converting, for: job.id)
        }

        isConverting = true
        errorMessage = nil

        let registry = self.registry
        let options = settings.options
        let limit = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4))

        conversionTask = Task { [weak self] in
            await withTaskGroup(of: JobOutcome.self) { group in
                var iterator = pending.makeIterator()
                var running = 0

                while running < limit, let job = iterator.next() {
                    group.addTask {
                        await Self.convert(job: job, registry: registry, options: options)
                    }
                    running += 1
                }

                while let outcome = await group.next() {
                    self?.apply(outcome)

                    if let job = iterator.next() {
                        group.addTask {
                            await Self.convert(job: job, registry: registry, options: options)
                        }
                    }
                }
            }

            self?.isConverting = false
            self?.conversionTask = nil
        }
    }

    /// Cancels the conversion run in progress, returning jobs to the queue.
    func cancel() {
        conversionTask?.cancel()
        conversionTask = nil
        isConverting = false

        for job in jobs where job.status == .converting {
            updateStatus(.waiting, for: job.id)
        }
    }

    /// Waits for the conversion run in progress to finish.
    ///
    /// Returns immediately when nothing is running.
    func waitForConversionToFinish() async {
        await conversionTask?.value
    }

    /// The outcome of converting a single document.
    private struct JobOutcome: Sendable {
        let id: ConversionJob.ID
        let result: Result<ConversionResult, ConversionFailure>
    }

    /// A conversion failure reduced to a message, so it can cross actor
    /// boundaries without carrying a non-`Sendable` error.
    private struct ConversionFailure: Error, Sendable {
        let message: String
        let wasCancelled: Bool
    }

    /// Converts one document off the main actor.
    ///
    /// Access to the document is wrapped in a security scoped resource so the
    /// sandboxed app can read files the user chose in an earlier session.
    nonisolated private static func convert(
        job: ConversionJob,
        registry: ConverterRegistry,
        options: ConversionOptions
    ) async -> JobOutcome {
        let url = job.sourceURL
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let result = try await registry.convert(url: url, options: options)
            return JobOutcome(id: job.id, result: .success(result))
        } catch is CancellationError {
            return JobOutcome(
                id: job.id,
                result: .failure(ConversionFailure(message: "Cancelled.", wasCancelled: true))
            )
        } catch {
            return JobOutcome(
                id: job.id,
                result: .failure(
                    ConversionFailure(message: Self.describe(error), wasCancelled: false)
                )
            )
        }
    }

    /// Reduces an error to a sentence suitable for display beside a job.
    nonisolated private static func describe(_ error: any Error) -> String {
        guard let localized = error as? any LocalizedError,
              let description = localized.errorDescription else {
            return error.localizedDescription
        }
        guard let suggestion = localized.recoverySuggestion else { return description }
        return "\(description) \(suggestion)"
    }

    private func apply(_ outcome: JobOutcome) {
        guard let index = jobs.firstIndex(where: { $0.id == outcome.id }) else { return }

        switch outcome.result {
        case .success(let result):
            jobs[index].result = result
            jobs[index].status = .converted

        case .failure(let failure):
            jobs[index].result = nil
            jobs[index].status = failure.wasCancelled ? .waiting : .failed(failure.message)
        }
    }

    private func updateStatus(_ status: JobStatus, for id: ConversionJob.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = status
    }

    // MARK: - Saving

    /// Writes every converted job into `directory`.
    ///
    /// - Returns: The number of files written.
    @discardableResult
    func saveAll(to directory: URL) -> Int {
        let needsScope = directory.startAccessingSecurityScopedResource()
        defer {
            if needsScope { directory.stopAccessingSecurityScopedResource() }
        }

        var written = 0
        var failures: [String] = []

        for job in convertedJobs {
            guard let markdown = job.markdown else { continue }
            let destination = directory.appending(path: job.suggestedFileName)
            do {
                try markdown.write(to: destination, atomically: true, encoding: .utf8)
                for asset in job.result?.assets ?? [] {
                    try asset.write(relativeTo: directory)
                }
                written += 1
            } catch {
                failures.append(job.displayName)
            }
        }

        if !failures.isEmpty {
            errorMessage = "Could not save \(failures.joined(separator: ", "))."
        }

        return written
    }
}
