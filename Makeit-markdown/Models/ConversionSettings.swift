import Foundation
import MarkdownKit
import Observation

/// The user's conversion preferences, persisted in user defaults.
///
/// These settings belong to the app alone. The command line tool deliberately
/// reads no shared configuration, so that a given invocation behaves the same
/// way regardless of how the app happens to be set up.
@MainActor
@Observable
final class ConversionSettings {

    private enum Key {
        static let detectHeadings = "conversion.detectHeadings"
        static let detectLists = "conversion.detectLists"
        static let insertPageBreaks = "conversion.insertPageBreaks"
        static let experimentalTableExtraction = "conversion.experimentalTableExtraction"
        static let normalizeWhitespace = "conversion.normalizeWhitespace"
        static let stripRepeatedPageFurniture = "conversion.stripRepeatedPageFurniture"
        static let extractGraphics = "conversion.extractGraphics"
    }

    private let defaults: UserDefaults

    var detectHeadings: Bool {
        didSet { defaults.set(detectHeadings, forKey: Key.detectHeadings) }
    }

    var detectLists: Bool {
        didSet { defaults.set(detectLists, forKey: Key.detectLists) }
    }

    var insertPageBreaks: Bool {
        didSet { defaults.set(insertPageBreaks, forKey: Key.insertPageBreaks) }
    }

    var experimentalTableExtraction: Bool {
        didSet { defaults.set(experimentalTableExtraction, forKey: Key.experimentalTableExtraction) }
    }

    var normalizeWhitespace: Bool {
        didSet { defaults.set(normalizeWhitespace, forKey: Key.normalizeWhitespace) }
    }

    var stripRepeatedPageFurniture: Bool {
        didSet {
            defaults.set(stripRepeatedPageFurniture, forKey: Key.stripRepeatedPageFurniture)
        }
    }

    var extractGraphics: Bool {
        didSet { defaults.set(extractGraphics, forKey: Key.extractGraphics) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let fallback = ConversionOptions.default
        defaults.register(defaults: [
            Key.detectHeadings: fallback.detectHeadings,
            Key.detectLists: fallback.detectLists,
            Key.insertPageBreaks: fallback.insertPageBreaks,
            Key.experimentalTableExtraction: fallback.experimentalTableExtraction,
            Key.normalizeWhitespace: fallback.normalizeWhitespace,
            Key.stripRepeatedPageFurniture: fallback.stripRepeatedPageFurniture,
            Key.extractGraphics: fallback.extractGraphics
        ])

        detectHeadings = defaults.bool(forKey: Key.detectHeadings)
        detectLists = defaults.bool(forKey: Key.detectLists)
        insertPageBreaks = defaults.bool(forKey: Key.insertPageBreaks)
        experimentalTableExtraction = defaults.bool(forKey: Key.experimentalTableExtraction)
        normalizeWhitespace = defaults.bool(forKey: Key.normalizeWhitespace)
        stripRepeatedPageFurniture = defaults.bool(forKey: Key.stripRepeatedPageFurniture)
        extractGraphics = defaults.bool(forKey: Key.extractGraphics)
    }

    /// The settings expressed as options for ``MarkdownKit``.
    var options: ConversionOptions {
        ConversionOptions(
            detectHeadings: detectHeadings,
            detectLists: detectLists,
            insertPageBreaks: insertPageBreaks,
            experimentalTableExtraction: experimentalTableExtraction,
            normalizeWhitespace: normalizeWhitespace,
            stripRepeatedPageFurniture: stripRepeatedPageFurniture,
            extractGraphics: extractGraphics
        )
    }

    /// Restores every setting to its shipping default.
    func resetToDefaults() {
        let fallback = ConversionOptions.default
        detectHeadings = fallback.detectHeadings
        detectLists = fallback.detectLists
        insertPageBreaks = fallback.insertPageBreaks
        experimentalTableExtraction = fallback.experimentalTableExtraction
        normalizeWhitespace = fallback.normalizeWhitespace
        stripRepeatedPageFurniture = fallback.stripRepeatedPageFurniture
        extractGraphics = fallback.extractGraphics
    }
}
