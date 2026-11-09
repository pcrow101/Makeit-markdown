import Foundation
import Testing
@testable import Makeit_markdown
import MarkdownKit

@MainActor
@Suite("ConversionSettings")
struct ConversionSettingsTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
    }

    @Test("Settings start at the shipping defaults")
    func startsAtDefaults() {
        let settings = ConversionSettings(defaults: makeDefaults())
        #expect(settings.options == ConversionOptions.default)
    }

    @Test("Table extraction is on by default")
    func tablesOnByDefault() {
        let settings = ConversionSettings(defaults: makeDefaults())
        #expect(settings.extractTables)
    }

    @Test("Changes are reflected in the generated options")
    func optionsFollowSettings() {
        let settings = ConversionSettings(defaults: makeDefaults())
        settings.detectHeadings = false
        settings.insertPageBreaks = true
        settings.extractTables = false

        #expect(!settings.options.detectHeadings)
        #expect(settings.options.insertPageBreaks)
        #expect(!settings.options.extractTables)
    }

    @Test("Changes survive a restart")
    func settingsPersist() {
        let defaults = makeDefaults()

        let first = ConversionSettings(defaults: defaults)
        first.detectLists = false
        first.insertPageBreaks = true

        let second = ConversionSettings(defaults: defaults)
        #expect(!second.detectLists)
        #expect(second.insertPageBreaks)
    }

    @Test("Image extraction is on by default and persists when changed")
    func graphicsSetting() {
        let defaults = makeDefaults()
        let first = ConversionSettings(defaults: defaults)
        #expect(first.extractGraphics)
        #expect(first.options.extractGraphics)

        first.extractGraphics = false
        #expect(!ConversionSettings(defaults: defaults).extractGraphics)

        first.resetToDefaults()
        #expect(first.extractGraphics)
    }

    @Test("The spreadsheet row limit defaults to 1,000, persists and resets")
    func spreadsheetRowLimit() {
        let defaults = makeDefaults()
        let first = ConversionSettings(defaults: defaults)
        #expect(first.maxSpreadsheetRows == 1_000)
        #expect(first.options.maxSpreadsheetRows == 1_000)

        first.maxSpreadsheetRows = 250
        #expect(ConversionSettings(defaults: defaults).maxSpreadsheetRows == 250)
        #expect(first.options.maxSpreadsheetRows == 250)

        first.resetToDefaults()
        #expect(first.maxSpreadsheetRows == 1_000)
    }

    @Test("A negative row limit is treated as no limit")
    func negativeRowLimit() {
        let settings = ConversionSettings(defaults: makeDefaults())
        settings.maxSpreadsheetRows = -5
        #expect(settings.options.maxSpreadsheetRows == 0)
    }

    @Test("Restoring defaults undoes every change")
    func resetToDefaults() {
        let settings = ConversionSettings(defaults: makeDefaults())
        settings.detectHeadings = false
        settings.detectLists = false
        settings.insertPageBreaks = true
        settings.extractTables = false
        settings.normalizeWhitespace = false
        settings.stripRepeatedPageFurniture = false

        settings.resetToDefaults()

        #expect(settings.options == ConversionOptions.default)
        #expect(settings.stripRepeatedPageFurniture)
    }
}
