import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves the pictures found in a word processing document as image files
/// that the Markdown output references.
///
/// PNG, JPEG and GIF pictures are saved unchanged. Other bitmap formats, such
/// as TIFF and BMP, are converted to PNG. Formats that cannot be decoded, such
/// as EMF and WMF drawings, are skipped and counted so a warning can name them.
struct WordImageStore {

    /// Whether pictures are saved at all.
    let isEnabled: Bool

    private let folder: String
    private let encodedFolder: String

    private(set) var assets: [ConversionAsset] = []

    /// Pictures whose format could not be converted.
    private(set) var unsupportedCount = 0

    /// Pictures referenced by the document but missing from it.
    private(set) var missingCount = 0

    /// Paths of pictures already saved, so a picture used twice is saved once.
    private var savedPaths: [String: String] = [:]

    init(documentURL: URL, isEnabled: Bool) {
        self.isEnabled = isEnabled
        let stem = documentURL.deletingPathExtension().lastPathComponent
        folder = "\(stem)_images"
        encodedFolder = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder
    }

    /// Saves `data` and returns the block that shows it, or `nil` when
    /// pictures are disabled or the data cannot be used.
    ///
    /// - Parameters:
    ///   - data: The picture's bytes, or `nil` when it could not be found.
    ///   - key: Identifies the picture within the document, such as its path.
    ///   - altText: The picture's description, when the document gives one.
    mutating func block(for data: Data?, key: String, altText: String) -> DocumentBlock? {
        guard isEnabled else { return nil }
        guard let data else {
            missingCount += 1
            return nil
        }

        let path: String
        if let existing = savedPaths[key] {
            path = existing
        } else {
            guard let (bytes, fileExtension) = Self.webReady(data) else {
                unsupportedCount += 1
                return nil
            }
            let name = "image-\(assets.count + 1).\(fileExtension)"
            assets.append(ConversionAsset(relativePath: "\(folder)/\(name)", data: bytes))
            path = "\(encodedFolder)/\(name)"
            savedPaths[key] = path
        }

        let trimmed = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let alt = trimmed.isEmpty ? "Image \(savedPaths.count)" : trimmed
        return .image(path: path, altText: alt.replacingOccurrences(of: "\n", with: " "))
    }

    /// Warnings describing pictures that could not be saved.
    var warnings: [ConversionWarning] {
        var warnings: [ConversionWarning] = []
        if unsupportedCount > 0 {
            warnings.append(ConversionWarning(
                kind: .unsupportedFeature,
                message: "\(Self.pictures(unsupportedCount)) could not be converted because "
                    + "their format is not supported, such as EMF or WMF drawings."
            ))
        }
        if missingCount > 0 {
            warnings.append(ConversionWarning(
                kind: .unsupportedFeature,
                message: "\(Self.pictures(missingCount)) referenced by the document could not be found."
            ))
        }
        return warnings
    }

    static func pictures(_ count: Int) -> String {
        count == 1 ? "1 picture" : "\(count) pictures"
    }

    // MARK: - Formats

    /// The bytes and extension to save for `data`, converting formats that
    /// Markdown viewers cannot show.
    static func webReady(_ data: Data) -> (Data, String)? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "png") }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "jpg") }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return (data, "gif") }
        return pngData(from: data).map { ($0, "png") }
    }

    private static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
