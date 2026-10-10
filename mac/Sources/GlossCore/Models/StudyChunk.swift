import Foundation

// 質問の答えから AI が抜き出した、覚えるべき単語やフレーズ
public struct StudyChunk: Equatable, Identifiable, Sendable {
    public var expression: String
    public var meaning: String
    public var id: String { expression.lowercased() }

    public init(expression: String, meaning: String) {
        self.expression = expression
        self.meaning = meaning
    }
}
