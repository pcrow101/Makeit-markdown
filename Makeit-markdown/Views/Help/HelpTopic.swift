import Foundation

/// A page of in-app help.
///
/// Content is held as Markdown in the binary rather than as bundled resource
/// files, so that help is always available and can be unit tested without
/// depending on how the app bundle happens to be assembled.
enum HelpTopic: String, CaseIterable, Identifiable, Sendable {

    case gettingStarted
    case supportedFormats
    case conversionOptions
    case images
    case commandLine
    case troubleshooting

    var id: String { rawValue }

    /// The title shown in the sidebar and as the page heading.
    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .supportedFormats: return "Supported Formats"
        case .conversionOptions: return "Conversion Options"
        case .images: return "Images"
        case .commandLine: return "Command Line"
        case .troubleshooting: return "Troubleshooting"
        }
    }

    /// The SF Symbol shown beside the title.
    var symbol: String {
        switch self {
        case .gettingStarted: return "sparkles"
        case .supportedFormats: return "doc.on.doc"
        case .conversionOptions: return "slider.horizontal.3"
        case .images: return "photo"
        case .commandLine: return "terminal"
        case .troubleshooting: return "lifepreserver"
        }
    }

    /// The body of the page, written in Markdown.
    var body: String {
        switch self {
        case .gettingStarted: return Self.gettingStartedBody
        case .supportedFormats: return Self.supportedFormatsBody
        case .conversionOptions: return Self.conversionOptionsBody
        case .images: return Self.imagesBody
        case .commandLine: return Self.commandLineBody
        case .troubleshooting: return Self.troubleshootingBody
        }
    }

    // MARK: - Content

    private static let gettingStartedBody = """
        Makeit-Markdown converts documents into Markdown, a plain text format \
        that large language models read far more reliably than PDF or Word files.

        **Add documents**

        - Drag documents onto the window, or
        - Choose **File ▸ Open…** (⌘O), or
        - Click **Add Documents** in the toolbar.

        **Convert**

        Click **Convert** in the toolbar. Documents are converted in parallel, \
        and each row shows its progress.

        **Review and save**

        Select a document to see its Markdown. Switch between the raw source \
        and a rendered preview using the control at the top of the window. The \
        preview draws headings, lists, quotes, code and tables; the source view \
        is always the exact text that will be saved. \
        When you are happy, choose **File ▸ Save Markdown…** (⌘S) and pick a \
        folder; one `.md` file is written per converted document.
        """

    private static let supportedFormatsBody = """
        **Available now**

        - **PDF** (`.pdf`) — text, headings and lists are recovered. Documents \
        that contain only scanned images cannot be converted, because \
        Makeit-Markdown does not perform text recognition.

        - **Excel** (`.xlsx`) — each visible sheet becomes a heading followed \
        by a table, with the first row as the header. Formulas show their last \
        calculated value and dates are written as `YYYY-MM-DD`. Sheets are cut \
        at the row limit set in Settings. Charts and pictures are not \
        converted, and a warning names the sheets that hold them. Older `.xls` \
        workbooks must be saved as `.xlsx` first.

        - **Word** (`.docx`, `.doc`) — headings, lists, tables, quotes and \
        code samples are kept, and pictures are saved as image files. In a \
        `.docx` document, headings and lists come from the document's own \
        styles. A `.doc` file is read whatever it holds: an older Word \
        97–2003 document, RTF, or a web page saved as `.doc`, such as a \
        Confluence export to Word. Bold, italics and links are not kept, \
        charts are not converted, and password protected documents cannot be \
        opened.
        """

    private static let conversionOptionsBody = """
        Open **Settings** (⌘,) to change how documents are converted.

        **Detect headings**

        Infers Markdown headings by comparing each line's type size and weight \
        against the body text. Turn this off if a document's styling produces \
        headings where you expect paragraphs.

        **Detect lists**

        Recognises bulleted and numbered lines and emits Markdown lists.

        **Separate pages with a horizontal rule**

        Inserts `---` between pages. Useful when page boundaries carry meaning, \
        but it adds noise for continuous prose.

        **Collapse blank lines**

        Removes repeated blank lines so the output stays compact. This reduces \
        the token count when the Markdown is passed to a model.

        **Remove repeated headers and footers**

        Drops a line that appears near the top or bottom of most pages, such as \
        a confidentiality banner or a page number. Once the pages are joined \
        into one file such lines add nothing and interrupt the surrounding \
        prose. Page numbers are matched regardless of the number itself, so \
        "Page 1 of 20" and "Page 2 of 20" count as the same footer. Documents \
        of fewer than three pages are left alone, because repetition across so \
        few pages is weak evidence.

        **Reconstruct tables**

        On by default. A PDF stores positioned glyphs rather than table \
        structure, so tables are rebuilt from the geometry of the page. Check \
        complex tables against the original document. Turn this off to keep \
        table text as plain lines.

        Tables are found by alignment: several lines placing their text at the \
        same horizontal positions. A grid is only emitted when it holds at \
        least two rows and two columns and most of its cells carry text, so a \
        region that cannot be read confidently stays as prose rather than \
        becoming a misleading table. Tables that use merged cells are the usual \
        reason a region is left alone.

        **Maximum rows per sheet**

        Applies to Excel workbooks. Each sheet is cut after this many rows \
        below its header, and a warning says how many rows were left out. \
        The limit applies to every sheet separately. Enter 0 to keep every row.
        """

    private static let imagesBody = """
        Pictures, drawings and charts in a PDF are saved as PNG files and \
        linked from the Markdown in reading order, for example \
        `![Figure 1 (page 2)](report_images/page-2-figure-1.png)`.

        Pictures in a Word document are saved too, using the picture's \
        description as its caption, for example \
        `![System diagram](report_images/image-1.png)`. Pictures in formats \
        a Markdown viewer cannot show, such as EMF or WMF drawings, are \
        skipped with a warning.

        **Where the images go**

        Images are written to a `<name>_images` folder beside the `.md` file \
        when you choose **File ▸ Save Markdown…**. Keep that folder with the \
        Markdown file, or the links will not resolve.

        **Turn it on or off**

        Open **Settings** (⌘,) and use **Extract pictures, drawings and \
        charts**. It is on by default. When it is off, no images are saved and \
        no image links are written. The command line tool uses `--no-graphics`.

        **The preview**

        The rendered preview shows each image fitted to the window width. \
        Double-click an image to open it in its own resizable window. \
        In that window, zoom with the toolbar buttons, **⌘+** and **⌘-**, or a \
        pinch gesture, and scroll to move around. **⌘0** fits the image to \
        the window and **⌘1** shows it at its actual size.

        **Limits**

        Embedded pictures are always found. Vector drawings are detected by \
        heuristics, so a diagram made only of boxes and straight lines can be \
        missed. Pages with a rotation are skipped.
        """

    private static let commandLineBody = """
        The same conversion engine ships as a standalone tool, so documents can \
        be converted from scripts and build pipelines.

        The command line tool runs outside the app sandbox and keeps its own \
        settings: every option is given as a flag, and nothing is shared with \
        the app's preferences.

        **Convert one document**

        ```
        makeit-markdown report.pdf
        ```

        Writes `report.md` beside the source document.

        **Write to standard output**

        ```
        makeit-markdown report.pdf --stdout
        ```

        Diagnostics go to standard error, so the Markdown can be piped safely. \
        Images cannot be saved when writing to standard output.

        **Convert a folder**

        ```
        makeit-markdown ~/Documents --recursive --output ~/Markdown
        ```

        **Options**

        - `-o`, `--output` — destination folder, or file for a single document
        - `--stdout` — write Markdown to standard output
        - `-r`, `--recursive` — search folders recursively
        - `-f`, `--overwrite` — replace existing Markdown files
        - `--no-tables` — do not reconstruct tables
        - `--keep-page-furniture` — keep repeated headers and footers
        - `--no-graphics` — do not extract images
        - `--max-rows` — most rows per spreadsheet sheet (0 for no limit)
        - `-q`, `--quiet` — suppress progress messages

        The tool exits with `0` on success, `1` if a document failed to \
        convert, and `2` if the arguments could not be used.
        """

    private static let troubleshootingBody = """
        **A spreadsheet is cut short**

        Each sheet is limited to the number of rows set under **Maximum rows \
        per sheet** in Settings, 1,000 by default. Raise the limit, or enter 0 \
        to keep every row. On the command line use `--max-rows`.

        **Images are missing**

        Check that **Extract pictures, drawings and charts** is on in \
        Settings, and that the `_images` folder sits beside the `.md` file. \
        Images are not saved with `--stdout`.

        **"No text could be extracted"**

        The document most likely contains scanned images rather than text. \
        Makeit-Markdown does not perform optical character recognition. Run the \
        file through a text recognition tool first, then convert the result.

        **"The file is password protected"**

        Remove the password in the original application and convert the \
        unprotected copy.

        **Headings appear as ordinary paragraphs**

        Heading detection compares type sizes. If a document sets every line at \
        the same size, there is nothing to detect. Converting with headings \
        turned off gives a cleaner result in that case.

        **Paragraphs are broken in the wrong places**

        Text in a PDF has no paragraph structure, only lines. Lines are joined \
        until a sentence ends, which suits prose but not tightly set layouts \
        such as forms.

        **Tables look wrong**

        Tables are rebuilt from the positions of text, so unusual layouts can \
        be misread. If the result is not usable, turn off **Reconstruct \
        tables** in Settings and the table will appear as plain text.
        """
}
