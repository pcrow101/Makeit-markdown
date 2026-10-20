import ArgumentParser
import Foundation
import MarkdownKit

/// The `makeit-markdown` command line interface.
///
/// The tool is a thin shell over ``ConverterRegistry``. All behaviour is driven
/// by flags: it deliberately reads no configuration file and no user defaults,
/// so a given invocation always produces the same result regardless of how the
/// companion app happens to be configured.
@main
struct MakeitMarkdownCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "makeit-markdown",
        abstract: "Convert documents into an AI friendly Markdown format.",
        discussion: """
            Converts PDF documents into Markdown. Word and Excel documents are \
            recognised but not yet supported.

            Examples:
              makeit-markdown report.pdf
              makeit-markdown report.pdf --stdout
              makeit-markdown ~/Documents --recursive --output ~/Markdown
            """,
        version: MakeitMarkdownCommand.versionString
    )

    // MARK: - Arguments

    @Argument(
        help: ArgumentHelp(
            "The documents or directories to convert.",
            valueName: "input"
        ),
        completion: .file()
    )
    var inputs: [String] = []

    @Option(
        name: [.customShort("o"), .long],
        help: ArgumentHelp(
            "The destination directory, or file when converting a single input.",
            valueName: "path"
        ),
        completion: .directory
    )
    var output: String?

    @Flag(name: .long, help: "Write Markdown to standard output instead of to a file.")
    var stdout = false

    @Flag(name: [.customShort("r"), .long], help: "Search directories recursively.")
    var recursive = false

    @Flag(name: [.customShort("f"), .long], help: "Overwrite existing Markdown files.")
    var overwrite = false

    @Flag(
        name: .long,
        help: """
            Attempt to reconstruct tables. Experimental: results are unreliable \
            and should be checked against the source.
            """
    )
    var experimentalTables = false

    @Flag(
        name: .long,
        help: """
            Keep running headers and footers. By default a line repeated near \
            the edge of most pages, such as a confidentiality banner or page \
            number, is removed.
            """
    )
    var keepPageFurniture = false

    @Flag(
        name: .long,
        help: "Do not extract pictures, drawings and charts as image files."
    )
    var noGraphics = false

    @Flag(name: [.customShort("q"), .long], help: "Suppress progress messages.")
    var quiet = false

    // MARK: - Validation

    func validate() throws {
        guard !inputs.isEmpty else {
            throw ValidationError("Specify at least one file or directory to convert.")
        }
        guard !(stdout && output != nil) else {
            throw ValidationError("Specify either --stdout or --output, not both.")
        }
    }

    // MARK: - Execution

    func run() async throws {
        let registry = ConverterRegistry.standard
        let resolver = InputResolver(registry: registry)

        let urls: [URL]
        do {
            urls = try resolver.resolve(paths: inputs, recursive: recursive)
        } catch let failure as InputResolver.Failure {
            throw ExitCode.usageFailure(failure.message, path: failure.path)
        }

        guard !urls.isEmpty else {
            StandardStream.error("makeit-markdown: no convertible documents were found.")
            throw ExitCode.noInput
        }

        let destination = try resolveDestination(for: urls)
        var failureCount = 0

        for url in urls {
            do {
                try await convert(url: url, registry: registry, destination: destination)
            } catch {
                failureCount += 1
                StandardStream.error("makeit-markdown: \(url.lastPathComponent): \(error.cliDescription)")
            }
        }

        if failureCount > 0 {
            throw ExitCode.conversionFailure
        }
    }

    private func convert(
        url: URL,
        registry: ConverterRegistry,
        destination: Destination
    ) async throws {
        let result = try await registry.convert(url: url, options: conversionOptions)

        if !quiet {
            for warning in result.warnings {
                StandardStream.error("makeit-markdown: \(url.lastPathComponent): warning: \(warning.message)")
            }
        }

        switch destination {
        case .standardOutput:
            StandardStream.outRaw(result.markdown)
            if !result.assets.isEmpty && !quiet {
                StandardStream.error(
                    "makeit-markdown: \(url.lastPathComponent): warning: images are not saved when writing "
                        + "to standard output; use --no-graphics to omit image references."
                )
            }

        case .file(let fileURL):
            try write(result, to: fileURL, source: url)

        case .directory(let directoryURL):
            try write(
                result,
                to: directoryURL.appending(path: result.suggestedFileName),
                source: url
            )

        case .alongsideSource:
            try write(
                result,
                to: url.deletingPathExtension().appendingPathExtension("md"),
                source: url
            )
        }
    }

    private func write(_ result: ConversionResult, to url: URL, source: URL) throws {
        let markdown = result.markdown
        let path = url.path(percentEncoded: false)

        if FileManager.default.fileExists(atPath: path) && !overwrite {
            throw ConversionError.outputWriteFailed(
                url: url,
                reason: "the file already exists. Pass --overwrite to replace it."
            )
        }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ConversionError.outputWriteFailed(url: url, reason: error.localizedDescription)
        }

        do {
            for asset in result.assets {
                try asset.write(relativeTo: url.deletingLastPathComponent())
            }
        } catch {
            throw ConversionError.outputWriteFailed(url: url, reason: error.localizedDescription)
        }

        if !quiet {
            StandardStream.error("Converted \(source.lastPathComponent) to \(path)")
        }
    }

    // MARK: - Options

    /// The conversion options implied by the supplied flags.
    var conversionOptions: ConversionOptions {
        ConversionOptions(
            experimentalTableExtraction: experimentalTables,
            stripRepeatedPageFurniture: !keepPageFurniture,
            extractGraphics: !noGraphics
        )
    }

    /// Where converted Markdown should be written.
    enum Destination: Equatable {
        case standardOutput
        case file(URL)
        case directory(URL)
        case alongsideSource
    }

    /// Determines the destination, creating the output directory when needed.
    ///
    /// A single input paired with `--output` is treated as a file path unless
    /// the path already exists as a directory, which matches the behaviour of
    /// familiar tools such as `cp`.
    func resolveDestination(for urls: [URL]) throws -> Destination {
        if stdout { return .standardOutput }

        guard let output else { return .alongsideSource }

        let url = URL(filePath: output).standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )

        if exists && isDirectory.boolValue {
            return .directory(url)
        }
        if exists {
            guard urls.count == 1 else {
                throw ExitCode.usageFailure(
                    "the destination must be a directory when converting multiple documents",
                    path: output
                )
            }
            return .file(url)
        }
        if urls.count == 1 && url.pathExtension.lowercased() == "md" {
            try createDirectory(url.deletingLastPathComponent())
            return .file(url)
        }

        try createDirectory(url)
        return .directory(url)
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.outputWriteFailed(url: url, reason: error.localizedDescription)
        }
    }

    /// The version reported by `--version`, kept in step with the app.
    static let versionString = "1.0.0"
}

// MARK: - Exit codes

extension ExitCode {

    /// The inputs could not be interpreted.
    static let noInput = ExitCode(2)

    /// At least one document failed to convert.
    static let conversionFailure = ExitCode(1)

    /// Reports a usage problem on standard error and returns exit code 2.
    static func usageFailure(_ message: String, path: String) -> ExitCode {
        StandardStream.error("makeit-markdown: \(path): \(message)")
        return ExitCode(2)
    }
}

// MARK: - Diagnostics

extension Error {

    /// A single line description suitable for a terminal diagnostic.
    ///
    /// `LocalizedError` recovery suggestions are appended because they carry the
    /// actionable part of the message.
    fileprivate var cliDescription: String {
        guard let localized = self as? LocalizedError,
              let description = localized.errorDescription else {
            return localizedDescription
        }
        guard let suggestion = localized.recoverySuggestion else { return description }
        return "\(description) \(suggestion)"
    }
}
