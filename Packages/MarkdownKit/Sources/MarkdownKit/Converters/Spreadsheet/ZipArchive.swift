import Compression
import Foundation

/// A failure to read a ZIP container.
enum ZipArchiveError: Error, Equatable {
    /// The data is not a ZIP archive.
    case notAnArchive
    /// The archive is damaged or an entry does not match its header.
    case corrupt(String)
    /// An entry uses encryption.
    case encrypted
    /// An entry uses a compression method other than stored or deflate.
    case unsupportedCompression(Int)
    /// An entry or the archive uses ZIP64 extensions, which are not supported.
    case unsupportedZip64
    /// An entry would expand beyond the size limit.
    case entryTooLarge(String)
}

/// A minimal read-only ZIP reader.
///
/// It exists so Open XML documents can be read without a third party
/// dependency and without launching `unzip`, which the app sandbox forbids.
/// Only stored and deflate entries are supported, which covers every file
/// produced by Office applications.
struct ZipArchive {

    /// The largest entry that will be expanded, as a guard against archives
    /// crafted to exhaust memory.
    static let maximumEntrySize = 512 * 1024 * 1024

    private struct Entry {
        let flags: Int
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let headerOffset: Int
    }

    private static let endOfDirectorySignature = 0x0605_4B50
    private static let centralHeaderSignature = 0x0201_4B50
    private static let localHeaderSignature = 0x0403_4B50

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    /// The names of every file in the archive.
    var names: [String] { Array(entries.keys) }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        self.entries = try Self.readDirectory(of: bytes)
    }

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    /// The uncompressed contents of `name`, or `nil` when there is no such entry.
    func contents(of name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        guard (entry.flags & 1) == 0 else { throw ZipArchiveError.encrypted }
        guard entry.uncompressedSize <= Self.maximumEntrySize else {
            throw ZipArchiveError.entryTooLarge(name)
        }

        let start = try dataStart(of: entry)
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw ZipArchiveError.corrupt("truncated entry \(name)") }

        switch entry.method {
        case 0:
            return Data(bytes[start..<end])
        case 8:
            return try Self.inflate(
                Array(bytes[start..<end]),
                expectedSize: entry.uncompressedSize,
                name: name
            )
        default:
            throw ZipArchiveError.unsupportedCompression(entry.method)
        }
    }

    // MARK: - Reading the directory

    private static func readDirectory(of bytes: [UInt8]) throws -> [String: Entry] {
        guard let end = findEndOfDirectory(in: bytes) else { throw ZipArchiveError.notAnArchive }

        let count = try readInt(bytes, at: end + 10, width: 2)
        let directorySize = try readInt(bytes, at: end + 12, width: 4)
        let directoryOffset = try readInt(bytes, at: end + 16, width: 4)
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipArchiveError.unsupportedZip64
        }

        var entries: [String: Entry] = [:]
        var offset = directoryOffset

        for _ in 0..<count {
            guard try readInt(bytes, at: offset, width: 4) == centralHeaderSignature else {
                throw ZipArchiveError.corrupt("bad central directory")
            }
            let nameLength = try readInt(bytes, at: offset + 28, width: 2)
            let extraLength = try readInt(bytes, at: offset + 30, width: 2)
            let commentLength = try readInt(bytes, at: offset + 32, width: 2)

            let entry = Entry(
                flags: try readInt(bytes, at: offset + 8, width: 2),
                method: try readInt(bytes, at: offset + 10, width: 2),
                compressedSize: try readInt(bytes, at: offset + 20, width: 4),
                uncompressedSize: try readInt(bytes, at: offset + 24, width: 4),
                headerOffset: try readInt(bytes, at: offset + 42, width: 4)
            )
            if entry.compressedSize == 0xFFFF_FFFF || entry.uncompressedSize == 0xFFFF_FFFF {
                throw ZipArchiveError.unsupportedZip64
            }

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else {
                throw ZipArchiveError.corrupt("bad entry name")
            }
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8) ?? ""
            entries[name] = entry

            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The offset of the end of central directory record, searching backwards
    /// through the trailing comment.
    private static func findEndOfDirectory(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var offset = bytes.count - 22
        while offset >= lowest {
            if let value = try? readInt(bytes, at: offset, width: 4),
               value == endOfDirectorySignature {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private func dataStart(of entry: Entry) throws -> Int {
        guard try Self.readInt(bytes, at: entry.headerOffset, width: 4) == Self.localHeaderSignature
        else {
            throw ZipArchiveError.corrupt("bad local header")
        }
        let nameLength = try Self.readInt(bytes, at: entry.headerOffset + 26, width: 2)
        let extraLength = try Self.readInt(bytes, at: entry.headerOffset + 28, width: 2)
        return entry.headerOffset + 30 + nameLength + extraLength
    }

    // MARK: - Helpers

    /// Reads a little-endian unsigned integer of `width` bytes.
    private static func readInt(_ bytes: [UInt8], at offset: Int, width: Int) throws -> Int {
        guard offset >= 0, offset + width <= bytes.count else {
            throw ZipArchiveError.corrupt("unexpected end of archive")
        }
        var value = 0
        for index in 0..<width {
            value |= Int(bytes[offset + index]) << (8 * index)
        }
        return value
    }

    private static func inflate(_ source: [UInt8], expectedSize: Int, name: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var destination = [UInt8](repeating: 0, count: expectedSize)
        let written = compression_decode_buffer(
            &destination,
            expectedSize,
            source,
            source.count,
            nil,
            COMPRESSION_ZLIB
        )
        guard written == expectedSize else {
            throw ZipArchiveError.corrupt("could not expand \(name)")
        }
        return Data(destination)
    }
}
