import AppKit
import SwiftUI

/// Shows long text in a selectable, read-only `NSTextView`.
///
/// A SwiftUI `Text` lays out its whole string at once, which stalls the
/// interface for seconds once a converted spreadsheet runs to hundreds of
/// kilobytes. `NSTextView` lays out only what is on screen.
struct SourceTextView: NSViewRepresentable {

    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textContainerInset = NSSize(width: 12, height: 12)
            textView.string = text
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }
}
