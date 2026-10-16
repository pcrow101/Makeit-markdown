import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarkdownKit

@Suite("ConverterRegistry")
struct ConverterRegistryTests {

    @Test("The standard registry resolves PDF documents")
    func resolvesPDF() throws {
        let converter = try #require(ConverterRegistry.standard.converter(for: .pdf))
        #expect(converter.formatName == "PDF")
    }

    @Test("Word and Excel documents resolve to their stub converters", arguments: [
        ("docx", "Word"), ("xlsx", "Excel")
    ])
    func resolvesStubFormats(fileExtension: String, expectedName: String) throws {
        let type = try #require(UTType(filenameExtension: fileExtension))
        let converter = try #require(ConverterRegistry.standard.converter(for: type))
        #expect(converter.formatName == expectedName)
    }

    @Test("An unregistered type resolves to no converter")
    func unregisteredType() {
        #expect(ConverterRegistry.standard.converter(for: .png) == nil)
    }

    @Test("A missing file is reported before format resolution")
    func missingFile() async {
        let url = URL(filePath: "/nonexistent/\(UUID().uuidString).pdf")
        await #expect(throws: ConversionError.fileNotFound(url: url)) {
            try await ConverterRegistry.standard.convert(url: url)
        }
    }

    @Test("An unsupported format reports the offending extension")
    func unsupportedFormat() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "notes.rtf")
        try "plain".write(to: url, atomically: true, encoding: .utf8)

        await #expect(throws: ConversionError.unsupportedFormat(fileExtension: "rtf")) {
            try await ConverterRegistry.standard.convert(url: url)
        }
    }

    @Test("A registered but unshipped format reports that it is unavailable")
    func notYetImplemented() async throws {
        let scratch = try PDFFixture.Scratch()
        let url = scratch.directory.appending(path: "report.docx")
        try Data().write(to: url)

        await #expect(throws: ConversionError.notYetImplemented(format: "Word")) {
            try await ConverterRegistry.standard.convert(url: url)
        }
    }

    @Test("Supported extensions cover every shipping and planned format")
    func supportedExtensions() {
        let extensions = Set(ConverterRegistry.standard.supportedFileExtensions)
        #expect(extensions.contains("pdf"))
        #expect(extensions.contains("docx"))
        #expect(extensions.contains("xlsx"))
    }

    @Test("Converters are consulted in registration order")
    func registrationOrder() {
        let registry = ConverterRegistry(converters: [StubConverter(), PDFConverter()])
        #expect(registry.converter(for: .pdf)?.formatName == "Stub")
    }

    @Test("Errors carry an actionable recovery suggestion")
    func recoverySuggestions() {
        #expect(ConversionError.notYetImplemented(format: "Word").recoverySuggestion != nil)
        #expect(ConversionError.unsupportedFormat(fileExtension: "rtf").recoverySuggestion != nil)
        #expect(ConversionError.cancelled.recoverySuggestion == nil)
    }
}

/// A converter that claims PDFs, used to verify resolution order.
private struct StubConverter: DocumentConverter {
    let formatName = "Stub"
    var supportedTypes: [UTType] { [.pdf] }

    func convert(url: URL, options: ConversionOptions) async throws -> ConversionResult {
        ConversionResult(markdown: "stub\n", sourceURL: url)
    }
}
