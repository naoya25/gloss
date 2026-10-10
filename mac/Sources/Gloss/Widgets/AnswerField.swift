import AppKit
import SwiftUI

// テストの答えを書く1行の欄。Return で次の欄に移る。
// SwiftUI の TextField で Return のたびにフォーカスを動かすと、離れた欄の文字が消えることがあった。
// NSTextField なら、日本語の変換を確定する Return は入力メソッドが受け取り、ここには来ない
struct AnswerField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled = true
    var focusesOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = AnswerTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        if focusesOnAppear {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        // 入力中(変換中を含む)は書き戻さない。書き戻すと打っている途中の文字が消える
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AnswerField

        init(_ parent: AnswerField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // SwiftUI の中では次のキービューが決まっていないことがあるので、画面上で1つ下の欄を探して移る
            guard let window = control.window, let root = window.contentView else { return true }
            let fields = AnswerTextField.all(in: root).sorted { $0.windowY > $1.windowY }
            if let index = fields.firstIndex(where: { $0 === control }), index + 1 < fields.count {
                window.makeFirstResponder(fields[index + 1])
            } else {
                window.makeFirstResponder(nil)
            }
            return true
        }
    }
}

final class AnswerTextField: NSTextField {
    var windowY: CGFloat { convert(bounds, to: nil).maxY }

    static func all(in view: NSView) -> [AnswerTextField] {
        view.subviews.flatMap { subview -> [AnswerTextField] in
            if let field = subview as? AnswerTextField { return field.isEnabled ? [field] : [] }
            return all(in: subview)
        }
    }
}
