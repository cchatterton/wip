import AppKit
import SwiftUI

struct HighlightedNoteEditor: NSViewRepresentable {
    @Binding var text: String
    let findText: String
    let highlightHex: String
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length), length: 0))
        }
        context.coordinator.highlight(in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedNoteEditor
        private var lastText: String?
        private var lastFind: String?
        private var lastColour: String?

        init(_ parent: HighlightedNoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func highlight(in textView: NSTextView) {
            let text = textView.string
            let colourKey = "\(parent.highlightHex)-\(parent.colorScheme)"
            guard text != lastText || parent.findText != lastFind || colourKey != lastColour,
                  let storage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            if !parent.findText.isEmpty,
               let regex = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: parent.findText),
                options: [.caseInsensitive]
               ) {
                let colour = NSColor(WIPStyle.highlightSurface(
                    parent.colorScheme, hex: parent.highlightHex))
                for match in regex.matches(in: text, range: fullRange) {
                    storage.addAttribute(.backgroundColor, value: colour, range: match.range)
                }
            }
            storage.endEditing()
            lastText = text
            lastFind = parent.findText
            lastColour = colourKey
        }
    }
}
