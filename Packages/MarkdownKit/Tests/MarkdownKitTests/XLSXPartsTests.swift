import Foundation
import Testing

@testable import MarkdownKit

@Suite("Spreadsheet parts")
struct XLSXPartsTests {

    // MARK: - ZIP

    @Test("Stored and deflated entries are read back", arguments: [false, true])
    func readsEntries(deflate: Bool) throws {
        let archive = try ZipArchive(data: XLSXFixture.zip(
            [("a.txt", Data("alpha".utf8)), ("dir/b.txt", Data("bravo bravo bravo".utf8))],
            deflate: deflate
        ))

        #expect(try archive.contents(of: "a.txt") == Data("alpha".utf8))
        #expect(try archive.contents(of: "dir/b.txt") == Data("bravo bravo bravo".utf8))
        #expect(archive.contains("a.txt"))
    }

    @Test("A missing entry yields nothing")
    func missingEntry() throws {
        let archive = try ZipArchive(data: XLSXFixture.zip([("a.txt", Data("alpha".utf8))]))
        #expect(try archive.contents(of: "nope.txt") == nil)
    }

    @Test("Data that is not a ZIP archive is rejected")
    func notAnArchive() {
        #expect(throws: ZipArchiveError.notAnArchive) {
            try ZipArchive(data: Data("plain text, not a zip".utf8))
        }
        #expect(throws: ZipArchiveError.notAnArchive) {
            try ZipArchive(data: Data())
        }
    }

    @Test("A truncated archive is rejected rather than crashing")
    func truncatedArchive() {
        let data = XLSXFixture.zip([("a.txt", Data("alpha".utf8))])
        #expect(throws: ZipArchiveError.self) {
            _ = try ZipArchive(data: data.prefix(data.count - 10)).contents(of: "a.txt")
        }
    }

    // MARK: - Cell references

    @Test("Cell references become zero-based positions", arguments: [
        ("A1", 0, 0), ("B2", 1, 1), ("Z9", 25, 8), ("AA10", 26, 9), ("XFD1048576", 16_383, 1_048_575)
    ])
    func parsesReferences(text: String, column: Int, row: Int) {
        let reference = XLSXCellReference(text)
        #expect(reference?.column == column)
        #expect(reference?.row == row)
    }

    @Test("Malformed cell references are rejected", arguments: [
        "", "A", "1", "A0", "1A", "XFE1", "A1048577", "A-1"
    ])
    func rejectsReferences(text: String) {
        #expect(XLSXCellReference(text) == nil)
    }

    // MARK: - Number formats

    @Test("Format codes are classified by the tokens they use", arguments: [
        ("General", XLSXValueFormat.general),
        ("0.00", .general),
        ("#,##0", .general),
        ("[Red]0.00", .general),
        ("\"Total: \"0", .general),
        ("0.0%", .percent(decimals: 1)),
        ("0%", .percent(decimals: 0)),
        ("yyyy-mm-dd", .date(includesDate: true, includesTime: false, includesSeconds: false)),
        ("mmm-yy", .date(includesDate: true, includesTime: false, includesSeconds: false)),
        ("yyyy-mm-dd hh:mm", .date(includesDate: true, includesTime: true, includesSeconds: false)),
        ("h:mm:ss", .date(includesDate: false, includesTime: true, includesSeconds: true)),
        ("\"day\" 0", .general)
    ])
    func classifiesFormats(code: String, expected: XLSXValueFormat) {
        #expect(XLSXStyles.classify(code: code) == expected)
    }

    @Test("Unknown styles fall back to general")
    func unknownStyle() {
        #expect(XLSXStyles().format(forStyle: 7) == .general)
    }

    // MARK: - Paths

    @Test("Relationship targets resolve against the part that names them", arguments: [
        ("worksheets/sheet1.xml", "xl/", "xl/worksheets/sheet1.xml"),
        ("/xl/worksheets/sheet1.xml", "xl/", "xl/worksheets/sheet1.xml"),
        ("../drawings/drawing1.xml", "xl/worksheets/", "xl/drawings/drawing1.xml"),
        ("./styles.xml", "xl/", "xl/styles.xml")
    ])
    func resolvesTargets(target: String, directory: String, expected: String) {
        #expect(XLSXWorkbookReader.resolve(target, in: directory) == expected)
    }
}
