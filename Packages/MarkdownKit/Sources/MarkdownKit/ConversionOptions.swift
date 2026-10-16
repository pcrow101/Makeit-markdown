import Foundation
import UniformTypeIdentifiers

/// Options controlling how a source document is translated into Markdown.
///
/// Values are plain data so that both the sandboxed app and the standalone
/// command line tool can construct them independently. There is deliberately no
/// shared persistence between the two front ends.
public struct ConversionOptions: Sendable, Equatable, Codable {

    /// Infer Markdown headings from typographic cues in the source document.
    public var detectHeadings: Bool

    /// Infer ordered and unordered lists from line prefixes.
    public var detectLists: Bool

    /// Emit a thematic break between pages of a paginated document.
    public var insertPageBreaks: Bool

    /// Attempt to reconstruct tabular layouts.
    ///
    /// - Warning: Experimental. Table reconstruction from positional text is
    ///   unreliable and is disabled by default.
    public var experimentalTableExtraction: Bool

    /// Collapse runs of blank lines so the output stays compact for tokenisers.
    public var normalizeWhitespace: Bool

    /// Remove running headers and footers that repeat across pages.
    ///
    /// Confidentiality banners and page numbers carry no information once the
    /// pages are concatenated, and they interrupt the surrounding prose.
    public var stripRepeatedPageFurniture: Bool

    /// The default option set used when the caller expresses no preference.
    public static let `default` = ConversionOptions()

    public init(
        detectHeadings: Bool = true,
        detectLists: Bool = true,
        insertPageBreaks: Bool = false,
        experimentalTableExtraction: Bool = false,
        normalizeWhitespace: Bool = true,
        stripRepeatedPageFurniture: Bool = true
    ) {
        self.detectHeadings = detectHeadings
        self.detectLists = detectLists
        self.insertPageBreaks = insertPageBreaks
        self.experimentalTableExtraction = experimentalTableExtraction
        self.normalizeWhitespace = normalizeWhitespace
        self.stripRepeatedPageFurniture = stripRepeatedPageFurniture
    }
}
