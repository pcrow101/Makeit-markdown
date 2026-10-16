import Foundation

/// Removes running headers and footers that repeat across the pages of a
/// document.
///
/// Confidentiality banners, document titles and page numbers are repeated on
/// every page of many exported documents. They carry no information once the
/// pages are concatenated into a single Markdown file, and they interrupt the
/// surrounding prose, so they are stripped before structural analysis.
///
/// Detection is based on repetition rather than position, because extracted
/// text does not reliably carry page geometry. Only lines near the top and
/// bottom of a page are considered, so repeated body text is left alone.
struct PageFurnitureFilter {

    /// The most lines at each end of a page that may be treated as furniture.
    ///
    /// The effective depth shrinks on short pages so that the two edges can
    /// never between them cover the whole page.
    static let maximumEdgeDepth = 3

    /// The share of pages a line must appear on before it is considered
    /// furniture.
    static let repetitionThreshold = 0.6

    /// The fewest pages a document needs before repetition means anything.
    ///
    /// Two pages sharing a line is weak evidence, and stripping it from a short
    /// document risks losing real content.
    static let minimumPageCount = 3

    /// The longest line that may be matched ignoring its digits.
    ///
    /// Digit insensitive matching is how "Page 1 of 20" and "Page 2 of 20" are
    /// recognised as one footer, but it also makes genuinely different lines
    /// look alike. Restricting it to short outermost lines limits the damage.
    static let maximumNumberedFurnitureLength = 80

    /// Returns `pages` with repeated running headers and footers removed.
    static func strip(pages: [[TextLine]]) -> [[TextLine]] {
        guard pages.count >= minimumPageCount else { return pages }

        let required = Int((Double(pages.count) * repetitionThreshold).rounded(.up))
        let exact = repeatedLines(
            in: pages,
            required: required,
            outermostOnly: false,
            ignoringDigits: false
        )
        let numbered = repeatedLines(
            in: pages,
            required: required,
            outermostOnly: true,
            ignoringDigits: true
        )

        guard !exact.isEmpty || !numbered.isEmpty else { return pages }

        return pages.map { page in
            page.enumerated()
                .filter { index, line in
                    // The same wording appearing mid page is far more likely to
                    // be genuine content than a running header or footer.
                    guard isNearEdge(index: index, pageLineCount: page.count) else { return true }

                    if exact.contains(normalize(line.text)) { return false }

                    if isOutermost(index: index, pageLineCount: page.count),
                       line.text.count <= maximumNumberedFurnitureLength,
                       numbered.contains(normalizeIgnoringDigits(line.text)) {
                        return false
                    }

                    return true
                }
                .map(\.element)
        }
    }

    /// The normalised text of every line that repeats across enough pages.
    private static func repeatedLines(
        in pages: [[TextLine]],
        required: Int,
        outermostOnly: Bool,
        ignoringDigits: Bool
    ) -> Set<String> {
        var pagesContaining: [String: Int] = [:]

        for page in pages {
            // Count each distinct line once per page so that a line repeated
            // within a single page cannot reach the threshold on its own.
            var seen: Set<String> = []

            for (index, line) in page.enumerated() {
                let qualifies = outermostOnly
                    ? isOutermost(index: index, pageLineCount: page.count)
                    : isNearEdge(index: index, pageLineCount: page.count)
                guard qualifies else { continue }

                if ignoringDigits, line.text.count > maximumNumberedFurnitureLength { continue }

                let key = ignoringDigits
                    ? normalizeIgnoringDigits(line.text)
                    : normalize(line.text)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                pagesContaining[key, default: 0] += 1
            }
        }

        return Set(pagesContaining.filter { $0.value >= required }.keys)
    }

    /// How many lines at each end of a page count as the edge.
    static func edgeDepth(pageLineCount: Int) -> Int {
        max(1, min(maximumEdgeDepth, pageLineCount / 4))
    }

    private static func isNearEdge(index: Int, pageLineCount: Int) -> Bool {
        let depth = edgeDepth(pageLineCount: pageLineCount)
        return index < depth || index >= pageLineCount - depth
    }

    private static func isOutermost(index: Int, pageLineCount: Int) -> Bool {
        index == 0 || index == pageLineCount - 1
    }

    /// Reduces a line to a form that ignores case and spacing.
    static func normalize(_ text: String) -> String {
        var result = ""
        var lastWasSpace = true

        for character in text.lowercased() {
            if character.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Reduces a line to a form that also ignores the value of any numbers, so
    /// that "Page 1 of 20" and "Page 2 of 20" match.
    static func normalizeIgnoringDigits(_ text: String) -> String {
        var result = ""
        var lastWasDigit = false
        var lastWasSpace = true

        for character in text.lowercased() {
            if character.isNumber {
                if !lastWasDigit { result.append("#") }
                lastWasDigit = true
                lastWasSpace = false
            } else if character.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasDigit = false
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasDigit = false
                lastWasSpace = false
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
