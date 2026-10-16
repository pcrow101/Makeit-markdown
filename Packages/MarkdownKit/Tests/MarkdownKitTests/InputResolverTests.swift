import Foundation
import Testing
@testable import MarkdownKit
@testable import makeit_markdown

@Suite("InputResolver")
struct InputResolverTests {

    private let resolver = InputResolver(registry: .standard)

    /// Creates an empty file at `path` within `directory`, including any
    /// intermediate folders.
    private func touch(_ path: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
        return url
    }

    @Test("A named file is resolved")
    func singleFile() throws {
        let scratch = try PDFFixture.Scratch()
        let file = try touch("report.pdf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [file.path(percentEncoded: false)],
            recursive: false
        )

        #expect(resolved == [file.standardizedFileURL])
    }

    @Test("A named file of an unknown type is still resolved")
    func unsupportedFileIsResolved() throws {
        // Named files pass through so the converter can report a specific error
        // rather than the file silently disappearing from the run.
        let scratch = try PDFFixture.Scratch()
        let file = try touch("notes.rtf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [file.path(percentEncoded: false)],
            recursive: false
        )

        #expect(resolved.count == 1)
    }

    @Test("A missing path is reported")
    func missingPath() {
        #expect(throws: InputResolver.Failure.self) {
            _ = try resolver.resolve(paths: ["/nonexistent/\(UUID().uuidString)"], recursive: false)
        }
    }

    @Test("Duplicate paths are collapsed")
    func duplicatesCollapsed() throws {
        let scratch = try PDFFixture.Scratch()
        let file = try touch("report.pdf", in: scratch.directory)
        let path = file.path(percentEncoded: false)

        let resolved = try resolver.resolve(paths: [path, path], recursive: false)

        #expect(resolved.count == 1)
    }

    @Test("A directory yields only recognised documents")
    func directoryFiltersUnknownTypes() throws {
        let scratch = try PDFFixture.Scratch()
        _ = try touch("a.pdf", in: scratch.directory)
        _ = try touch("b.docx", in: scratch.directory)
        _ = try touch("notes.rtf", in: scratch.directory)
        _ = try touch("image.png", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: false
        )

        let names = resolved.map(\.lastPathComponent).sorted()
        #expect(names == ["a.pdf", "b.docx"])
    }

    @Test("Subdirectories are ignored unless the search is recursive")
    func nonRecursiveSearch() throws {
        let scratch = try PDFFixture.Scratch()
        _ = try touch("top.pdf", in: scratch.directory)
        _ = try touch("nested/deep.pdf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: false
        )

        #expect(resolved.map(\.lastPathComponent) == ["top.pdf"])
    }

    @Test("A recursive search descends into subdirectories")
    func recursiveSearch() throws {
        let scratch = try PDFFixture.Scratch()
        _ = try touch("top.pdf", in: scratch.directory)
        _ = try touch("nested/deep.pdf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: true
        )

        #expect(resolved.map(\.lastPathComponent).sorted() == ["deep.pdf", "top.pdf"])
    }

    @Test("Results are ordered deterministically")
    func deterministicOrdering() throws {
        let scratch = try PDFFixture.Scratch()
        for name in ["c.pdf", "a.pdf", "b.pdf"] {
            _ = try touch(name, in: scratch.directory)
        }

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: false
        )

        #expect(resolved.map(\.lastPathComponent) == ["a.pdf", "b.pdf", "c.pdf"])
    }

    @Test("Hidden files are skipped")
    func hiddenFilesSkipped() throws {
        let scratch = try PDFFixture.Scratch()
        _ = try touch("visible.pdf", in: scratch.directory)
        _ = try touch(".hidden.pdf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: false
        )

        #expect(resolved.map(\.lastPathComponent) == ["visible.pdf"])
    }

    @Test("An empty directory resolves to no documents")
    func emptyDirectory() throws {
        let scratch = try PDFFixture.Scratch()

        let resolved = try resolver.resolve(
            paths: [scratch.directory.path(percentEncoded: false)],
            recursive: true
        )

        #expect(resolved.isEmpty)
    }

    @Test("Files and directories can be mixed in one invocation")
    func mixedInputs() throws {
        let scratch = try PDFFixture.Scratch()
        let loose = try touch("loose.pdf", in: scratch.directory)
        let folder = scratch.directory.appending(path: "folder")
        _ = try touch("folder/inside.pdf", in: scratch.directory)

        let resolved = try resolver.resolve(
            paths: [
                loose.path(percentEncoded: false),
                folder.path(percentEncoded: false)
            ],
            recursive: false
        )

        #expect(resolved.map(\.lastPathComponent).sorted() == ["inside.pdf", "loose.pdf"])
    }
}
