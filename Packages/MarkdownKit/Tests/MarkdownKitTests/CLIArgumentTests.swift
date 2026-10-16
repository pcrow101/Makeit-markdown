import ArgumentParser
import Foundation
import Testing
@testable import MarkdownKit
@testable import makeit_markdown

@Suite("Command line interface")
struct CLIArgumentTests {

    // MARK: - Parsing

    @Test("A bare invocation converts one file alongside its source")
    func defaultInvocation() throws {
        let command = try MakeitMarkdownCommand.parse(["report.pdf"])
        #expect(command.inputs == ["report.pdf"])
        #expect(command.output == nil)
        #expect(!command.stdout)
        #expect(!command.recursive)
        #expect(!command.overwrite)
        #expect(!command.experimentalTables)
        #expect(!command.quiet)
    }

    @Test("Several inputs are accepted")
    func multipleInputs() throws {
        let command = try MakeitMarkdownCommand.parse(["a.pdf", "b.pdf", "c.pdf"])
        #expect(command.inputs == ["a.pdf", "b.pdf", "c.pdf"])
    }

    @Test("The output option accepts both its long and short spellings", arguments: [
        ["report.pdf", "-o", "out"],
        ["report.pdf", "--output", "out"]
    ])
    func outputSpellings(arguments: [String]) throws {
        let command = try MakeitMarkdownCommand.parse(arguments)
        #expect(command.output == "out")
    }

    @Test("Flags accept both their long and short spellings")
    func flagSpellings() throws {
        let long = try MakeitMarkdownCommand.parse(
            ["a.pdf", "--recursive", "--overwrite", "--quiet"]
        )
        #expect(long.recursive && long.overwrite && long.quiet)

        let short = try MakeitMarkdownCommand.parse(["a.pdf", "-r", "-f", "-q"])
        #expect(short.recursive && short.overwrite && short.quiet)
    }

    @Test("The experimental table flag maps onto conversion options")
    func experimentalTablesFlag() throws {
        let off = try MakeitMarkdownCommand.parse(["a.pdf"])
        #expect(!off.conversionOptions.experimentalTableExtraction)

        let on = try MakeitMarkdownCommand.parse(["a.pdf", "--experimental-tables"])
        #expect(on.conversionOptions.experimentalTableExtraction)
    }

    @Test("An unknown flag is rejected")
    func unknownFlag() {
        #expect(throws: (any Error).self) {
            _ = try MakeitMarkdownCommand.parse(["a.pdf", "--nonsense"])
        }
    }

    // MARK: - Validation

    @Test("At least one input is required")
    func inputsRequired() {
        var command = MakeitMarkdownCommand()
        command.inputs = []

        #expect(throws: ValidationError.self) {
            try command.validate()
        }
    }

    @Test("Standard output and a destination are mutually exclusive")
    func stdoutAndOutputConflict() {
        var command = MakeitMarkdownCommand()
        command.inputs = ["a.pdf"]
        command.stdout = true
        command.output = "out"

        #expect(throws: ValidationError.self) {
            try command.validate()
        }
    }

    @Test("Parsing rejects an invocation that fails validation")
    func parseAppliesValidation() {
        #expect(throws: (any Error).self) {
            _ = try MakeitMarkdownCommand.parse([])
        }
        #expect(throws: (any Error).self) {
            _ = try MakeitMarkdownCommand.parse(["a.pdf", "--stdout", "-o", "out"])
        }
    }

    @Test("A valid invocation passes validation")
    func validInvocation() throws {
        try MakeitMarkdownCommand.parse(["a.pdf", "--stdout"]).validate()
        try MakeitMarkdownCommand.parse(["a.pdf", "-o", "out"]).validate()
    }

    // MARK: - Destination resolution

    @Test("Standard output takes precedence over any other destination")
    func standardOutputDestination() throws {
        let command = try MakeitMarkdownCommand.parse(["a.pdf", "--stdout"])
        #expect(try command.resolveDestination(for: [URL(filePath: "a.pdf")]) == .standardOutput)
    }

    @Test("Without a destination the Markdown is written beside the source")
    func alongsideSourceDestination() throws {
        let command = try MakeitMarkdownCommand.parse(["a.pdf"])
        #expect(try command.resolveDestination(for: [URL(filePath: "a.pdf")]) == .alongsideSource)
    }

    @Test("An existing directory is used as the destination directory")
    func existingDirectoryDestination() throws {
        let scratch = try PDFFixture.Scratch()
        let command = try MakeitMarkdownCommand.parse(
            ["a.pdf", "-o", scratch.directory.path(percentEncoded: false)]
        )

        let destination = try command.resolveDestination(for: [URL(filePath: "a.pdf")])
        #expect(destination == .directory(scratch.directory.standardizedFileURL))
    }

    @Test("A single input with a Markdown destination writes that exact file")
    func singleFileDestination() throws {
        let scratch = try PDFFixture.Scratch()
        let target = scratch.directory.appending(path: "out.md")
        let command = try MakeitMarkdownCommand.parse(
            ["a.pdf", "-o", target.path(percentEncoded: false)]
        )

        let destination = try command.resolveDestination(for: [URL(filePath: "a.pdf")])
        #expect(destination == .file(target.standardizedFileURL))
    }

    @Test("A missing destination directory is created")
    func destinationDirectoryIsCreated() throws {
        let scratch = try PDFFixture.Scratch()
        let target = scratch.directory.appending(path: "nested/output")
        let command = try MakeitMarkdownCommand.parse(
            ["a.pdf", "b.pdf", "-o", target.path(percentEncoded: false)]
        )

        let destination = try command.resolveDestination(
            for: [URL(filePath: "a.pdf"), URL(filePath: "b.pdf")]
        )

        #expect(destination == .directory(target.standardizedFileURL))
        #expect(FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
    }

    @Test("Converting several documents into one existing file is refused")
    func multipleInputsIntoOneFile() throws {
        let scratch = try PDFFixture.Scratch()
        let target = scratch.directory.appending(path: "out.md")
        try "existing".write(to: target, atomically: true, encoding: .utf8)

        let command = try MakeitMarkdownCommand.parse(
            ["a.pdf", "b.pdf", "-o", target.path(percentEncoded: false)]
        )

        #expect(throws: ExitCode.self) {
            _ = try command.resolveDestination(
                for: [URL(filePath: "a.pdf"), URL(filePath: "b.pdf")]
            )
        }
    }

    // MARK: - Version

    @Test("The command advertises a version")
    func versionIsConfigured() {
        #expect(!MakeitMarkdownCommand.configuration.version.isEmpty)
        #expect(MakeitMarkdownCommand.configuration.commandName == "makeit-markdown")
    }
}
