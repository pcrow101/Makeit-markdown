import Foundation

/// How a numeric cell should be displayed.
enum XLSXValueFormat: Equatable {
    case general
    case date(includesDate: Bool, includesTime: Bool, includesSeconds: Bool)
    case percent(decimals: Int)
}

/// The number formats a workbook assigns to its cell styles.
struct XLSXStyles {

    /// Custom format codes keyed by their number format identifier.
    var customFormats: [Int: String] = [:]

    /// The number format identifier of each cell style, in style order.
    var cellFormatIDs: [Int] = []

    func format(forStyle index: Int) -> XLSXValueFormat {
        guard cellFormatIDs.indices.contains(index) else { return .general }
        let identifier = cellFormatIDs[index]

        if let code = customFormats[identifier] {
            return Self.classify(code: code)
        }
        return Self.builtIn(identifier) ?? .general
    }

    // MARK: - Classification

    private static func builtIn(_ identifier: Int) -> XLSXValueFormat? {
        switch identifier {
        case 9: return .percent(decimals: 0)
        case 10: return .percent(decimals: 2)
        case 18, 20, 32, 34: return .date(includesDate: false, includesTime: true, includesSeconds: false)
        case 19, 21, 33, 35, 45, 46, 47:
            return .date(includesDate: false, includesTime: true, includesSeconds: true)
        case 22: return .date(includesDate: true, includesTime: true, includesSeconds: false)
        case 14...17, 27...31, 36, 50...58:
            return .date(includesDate: true, includesTime: false, includesSeconds: false)
        default: return nil
        }
    }

    /// Classifies a custom format code by the tokens it uses.
    static func classify(code: String) -> XLSXValueFormat {
        let section = strippedLiterals(from: code).split(separator: ";", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let lowered = section.lowercased()

        if lowered.contains("%") {
            return .percent(decimals: decimalPlaces(in: lowered))
        }

        let hasHour = lowered.contains("h")
        let hasSecond = lowered.contains("s")
        let hasDate = lowered.contains("y") || lowered.contains("d")
            || (lowered.contains("m") && !hasHour && !hasSecond)

        guard hasDate || hasHour || hasSecond else { return .general }
        return .date(
            includesDate: hasDate,
            includesTime: hasHour || hasSecond,
            includesSeconds: hasSecond
        )
    }

    /// The format code without quoted text, escaped characters and `[...]`
    /// sections, none of which say what kind of value to expect.
    private static func strippedLiterals(from code: String) -> String {
        var result = ""
        var inQuotes = false
        var inBrackets = false
        var skipNext = false

        for character in code {
            if skipNext {
                skipNext = false
            } else if inQuotes {
                inQuotes = character != "\""
            } else if inBrackets {
                inBrackets = character != "]"
            } else if character == "\"" {
                inQuotes = true
            } else if character == "[" {
                inBrackets = true
            } else if character == "\\" || character == "_" || character == "*" {
                skipNext = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func decimalPlaces(in code: String) -> Int {
        guard let point = code.firstIndex(of: ".") else { return 0 }
        return code[code.index(after: point)...].prefix { $0 == "0" || $0 == "#" }.count
    }
}

/// Turns the raw numbers stored in a worksheet into the text a reader expects.
enum XLSXValueFormatter {

    /// Formats the numeric text `text` according to `format`.
    static func string(for text: String, format: XLSXValueFormat, uses1904Dates: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else { return trimmed }

        switch format {
        case .general:
            return plain(value)
        case .percent(let decimals):
            return String(format: "%.\(decimals)f%%", value * 100)
        case .date(let includesDate, let includesTime, let includesSeconds):
            return date(
                serial: value,
                uses1904Dates: uses1904Dates,
                includesDate: includesDate,
                includesTime: includesTime,
                includesSeconds: includesSeconds
            )
        }
    }

    /// A number without the floating point noise Excel stores, such as
    /// `0.30000000000000004`.
    static func plain(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%.15g", value)
    }

    private static func date(
        serial: Double,
        uses1904Dates: Bool,
        includesDate: Bool,
        includesTime: Bool,
        includesSeconds: Bool
    ) -> String {
        let totalSeconds = Int((serial * 86_400).rounded())
        let days = Int((Double(totalSeconds) / 86_400).rounded(.down))
        let secondsOfDay = totalSeconds - days * 86_400

        var pieces: [String] = []

        if includesDate {
            // Serial zero is 1899-12-30 in the 1900 system and 1904-01-01 in
            // the 1904 system.
            let epoch: TimeInterval = uses1904Dates ? -2_082_844_800 : -2_209_161_600
            let moment = Date(timeIntervalSince1970: epoch + Double(days) * 86_400)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let parts = calendar.dateComponents([.year, .month, .day], from: moment)
            pieces.append(String(
                format: "%04d-%02d-%02d",
                parts.year ?? 0,
                parts.month ?? 0,
                parts.day ?? 0
            ))
        }

        if includesTime {
            let hours = secondsOfDay / 3_600
            let minutes = (secondsOfDay % 3_600) / 60
            let seconds = secondsOfDay % 60
            pieces.append(includesSeconds
                ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%02d:%02d", hours, minutes))
        }

        return pieces.joined(separator: " ")
    }
}
