import AppKit
import SwiftUI

final class GlossNSTextView: NSTextView {
    var onImage: ((Data) -> Void)?
    var onPasteText: (() -> Void)?
    var onMouseSelect: ((String) -> Void)?

    // super の mouseDown はマウスを離すまで戻らないので、戻った時点で選択は確定している。
    // ダブルクリックの単語も、ドラッグで選んだフレーズも、ここで質問に回す
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let range = selectedRange()
        guard range.length > 0 else { return }
        onMouseSelect?((string as NSString).substring(with: range))
    }

    // プレーンテキストの NSTextView は画像の型を読めないので、画像だけのクリップボード
    // (⌘⇧⌃4 のスクショなど)だと ⌘V が無効になって paste(_:) まで来ない
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable, NSImage.canInit(with: NSPasteboard.general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let hasText = pasteboard.canReadObject(forClasses: [NSString.self], options: nil)
        if !hasText, let data = ImageEncoding.jpeg(from: pasteboard) {
            onImage?(data)
            return
        }
        let wasEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pasteAsPlainText(sender)
        if wasEmpty { onPasteText?() }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isEditable, NSImage.canInit(with: sender.draggingPasteboard) { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isEditable, let data = ImageEncoding.jpeg(from: sender.draggingPasteboard) {
            onImage?(data)
            return true
        }
        return super.performDragOperation(sender)
    }
}

struct GlossTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var onSelect: (String) -> Void = { _ in }
    var onImage: ((Data) -> Void)?
    var onPasteText: (() -> Void)?
    var onMouseSelect: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = GlossNSTextView(frame: .zero)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.typingAttributes = Self.attributes
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? GlossNSTextView else { return }
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.onImage = onImage
        textView.onPasteText = onPasteText
        textView.onMouseSelect = onMouseSelect
        if textView.string != text {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
        }
    }

    static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }()

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GlossTextView

        init(_ parent: GlossTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
            parent.onSelect(selected)
        }
    }
}
