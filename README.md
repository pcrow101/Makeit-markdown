# Makeit-Markdown

Converts PDF, Word and Excel documents into Markdown, a plain text format that
large language models read far more reliably than binary office formats.

A sandboxed SwiftUI app and a standalone command line tool share one conversion
engine, so a document converts identically whether it is dropped onto the
window or piped through a script.

## Status

| Format | Extensions      | State     |
| ------ | --------------- | --------- |
| PDF    | `.pdf`          | Supported |
| Word   | `.docx`, `.doc` | Supported |
| Excel  | `.xlsx`         | Supported |

Word documents keep their headings, lists, tables, quotes, code samples and
pictures; inline formatting such as bold and links is dropped. A `.docx` file is
read directly from its Open XML package. A `.doc` file is identified by its
contents: Word 97–2003 binary documents and RTF are read with AppKit's document
readers, and web pages saved as `.doc` (HTML or MHTML, as Confluence's "Export
to Word" produces) are read from their HTML, including embedded pictures.
Password protected Word documents cannot be opened, and charts are reported
with a warning rather than converted.

Legacy `.xls` workbooks are not supported; save them as `.xlsx` first.
Optical character recognition is out of scope: PDFs containing only scanned
images are reported rather than converted.

## Layout

```
Makeit-markdown/          The SwiftUI app (MVVM)
  Models/                 ConversionJob, ConversionSettings
  ViewModels/             ConversionViewModel
  Views/                  Window, preview, settings and help
Makeit-markdownTests/     App unit tests
Packages/MarkdownKit/     Conversion engine and command line tool
  Sources/MarkdownKit/    Converters, structure analysis, Markdown rendering
  Sources/makeit-markdown/ The command line interface
  Tests/                  Engine and CLI tests
```

All conversion logic lives in `MarkdownKit` and has no user interface
dependencies, which is what allows the app and the tool to share it.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Building

```
make build          # lint, then build the app
make test           # lint, then run both test suites
make lint-strict    # fail on any lint violation
```

## Command line tool

```
make install-cli    # installs to /usr/local/bin/makeit-markdown
```

Set `PREFIX` to install elsewhere, for example `make install-cli PREFIX=~/.local`.

```
makeit-markdown report.pdf                              # writes report.md alongside the source
makeit-markdown report.pdf --stdout                     # writes Markdown to standard output
makeit-markdown ~/Documents -r -o ~/Markdown            # converts a folder tree
```

Diagnostics go to standard error, so `--stdout` can be piped safely. The tool
exits `0` on success, `1` if a document failed to convert, and `2` if the
arguments could not be used.

The tool runs outside the app sandbox and takes all of its configuration from
flags. It deliberately shares no settings with the app, so a given invocation
always behaves the same way.

## Conversion options

| Option                  | Default | Effect                                      |
| ----------------------- | ------- | ------------------------------------------- |
| Detect headings         | on      | Infers headings from type size and weight   |
| Detect lists            | on      | Infers lists from line prefixes             |
| Insert page breaks      | off     | Emits `---` between pages                   |
| Collapse blank lines    | on      | Keeps output compact for tokenisers         |
| Reconstruct tables      | on      | Rebuilds tables as Markdown tables          |
| Maximum rows per sheet  | 1000    | Cuts each Excel sheet; 0 means no limit     |

## Testing

```
cd Packages/MarkdownKit && swift test    # engine and CLI
xcodebuild test -scheme Makeit-markdown -destination 'platform=macOS'
```

PDF fixtures are generated at test time with Core Graphics rather than being
committed as binaries, so the typographic properties each test depends on are
visible in the test itself.

## Checking real documents

The test fixtures are synthetic, so conversion quality should also be checked
against real documents. Put them in `Samples/Input` and run:

```
make samples                    # writes Markdown to Samples/Output
make samples NO_TABLES=1        # converts without table reconstruction
```

Everything under `Samples/` is ignored by git except its README, because real
documents are usually copyrighted or confidential. Conversion continues when an
individual document fails, so one bad file does not hide the rest.

When a real document exposes a bug, reproduce it as a generated fixture in
`Tests/MarkdownKitTests/Support/PDFFixture.swift` and add a regression test.
That keeps the fix covered without committing the original file.

## Table reconstruction

PDF stores positioned glyphs, not table structure, so tables are recovered by
geometry. It is on by default and can be turned off in Settings or with a
flag:

```
makeit-markdown report.pdf --no-tables
```

Lines are rebuilt from glyph positions rather than from the order the text was
written in, because that order interleaves the columns of a table into
unreadable prose. Columns are then found by alignment, and a grid is only
emitted when it has at least two rows and two columns and most of its cells
carry text. A region that fails those checks is left as prose, so an
unconvincing guess is never dressed up as a table.

Rows are separated by looking for the jump between the spacing of wrapped
lines inside a cell and the wider spacing between rows. The first such jump is
used rather than the widest, since the widest is often an unrelated break
before a sub heading, and treating that as the row spacing merges every row
into one.

Known limits: tables using merged cells are usually left as prose, and a cell
whose text wrapped mid word gains a space at the break, so "breakStart" may
appear as "breakSta rt".

## Excel workbooks

Workbooks are read directly from their Open XML package, so no spreadsheet
application is involved. Each visible sheet becomes a heading and a Markdown
table whose first row is the header:

```
makeit-markdown budget.xlsx
makeit-markdown budget.xlsx --max-rows 0     # keep every row
```

Formulas show the value Excel last calculated, since nothing is recalculated.
Dates are written as `YYYY-MM-DD`, percentages keep their format's precision,
and other numbers are shown without floating point noise. Hidden sheets and
empty rows are skipped. Merged cells show their value in the top left cell.

Each sheet is cut after `--max-rows` rows below the header (1,000 by default)
and a warning says how many were left out. Charts and pictures are not
converted; a warning names the sheets that hold them.
