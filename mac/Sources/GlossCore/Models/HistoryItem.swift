import Foundation

public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var source: String
    public var translation: String
    public var imageFile: String?
    // 翻訳先の指定。古い history.json には無いので、無いものは「自動」で訳したとみなす
    public var target: TranslationTarget?

    public init(source: String, translation: String, imageFile: String? = nil, target: TranslationTarget? = nil) {
        self.source = source
        self.translation = translation
        self.imageFile = imageFile
        self.target = target
    }

    // 同じ文を同じ翻訳先で文字だけ訳したものか。前後の空白と改行の違いは無視する。
    // 画像から訳したものは、書き起こしが同じでも画像が違いうるので対象にしない
    public func matches(source other: String, target otherTarget: TranslationTarget) -> Bool {
        imageFile == nil
            && (target ?? .auto) == otherTarget
            && source.trimmingCharacters(in: .whitespacesAndNewlines) == other.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var title: String {
        let line = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? (imageFile == nil ? "(empty)" : "Image") : line
    }
}
