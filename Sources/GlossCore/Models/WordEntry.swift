import Foundation

public struct WordEntry: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var term: String
    public var note: String
    public var context: String
    // ここから下はフラッシュカード用。古い words.json には無いので Optional にして、無くても読めるようにする
    public var english: String?
    public var japanese: String?
    public var example: String?
    public var exampleTranslation: String?
    public var flips: Int?
    public var lastReviewed: Date?
    public var mastery: Mastery?
    // 保存したときのエンジン。カードの訳と例文は、同じエンジンのときだけ自動で作る
    public var engine: Engine?
    // カードの訳と例文を作れなかった理由。入っている間は自動で作り直さない
    public var cardError: String?

    public init(term: String, note: String, context: String) {
        self.term = term
        self.note = note
        self.context = context
    }
}
