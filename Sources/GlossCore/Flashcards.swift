import Foundation

public enum Mastery: Int, Codable, CaseIterable, Identifiable, Sendable {
    case notYet = 0
    case unsure = 1
    case known = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .notYet: "覚えてない"
        case .unsure: "あやしい"
        case .known: "覚えた"
        }
    }
}

public enum CardFace: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case japanese

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .english: "英語"
        case .japanese: "日本語"
        }
    }
}

public enum WordSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case stale
    case fewestFlips
    case mastery
    case newest

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stale: "しばらく見ていない順"
        case .fewestFlips: "めくった回数が少ない順"
        case .mastery: "覚えていない順"
        case .newest: "追加した順"
        }
    }
}

extension WordEntry {
    public var flipCount: Int { flips ?? 0 }
    public var masteryLevel: Mastery { mastery ?? .notYet }
    public var hasCardPair: Bool { !(english ?? "").isEmpty && !(japanese ?? "").isEmpty }
    // 訳と例文がそろったら、もう AI に作らせない
    public var isCardComplete: Bool { hasCardPair && !(example ?? "").isEmpty && !(exampleTranslation ?? "").isEmpty }

    public func text(for face: CardFace) -> String {
        let value = face == .english ? english : japanese
        return (value ?? "").isEmpty ? term : value!
    }

    public mutating func recordFlip(at date: Date = Date()) {
        flips = flipCount + 1
        lastReviewed = date
    }
}

extension Array where Element == WordEntry {
    public func sorted(by order: WordSort) -> [WordEntry] {
        // 同じ値どうしは追加が新しい順にして、並びが毎回ぶれないようにする
        sorted { a, b in
            switch order {
            case .stale:
                let left = a.lastReviewed ?? .distantPast
                let right = b.lastReviewed ?? .distantPast
                if left != right { return left < right }
            case .fewestFlips:
                if a.flipCount != b.flipCount { return a.flipCount < b.flipCount }
            case .mastery:
                if a.masteryLevel != b.masteryLevel { return a.masteryLevel.rawValue < b.masteryLevel.rawValue }
            case .newest:
                break
            }
            return a.date > b.date
        }
    }
}

extension Prompts {
    public static func cardPair(term: String, context: String) -> String {
        """
        英単語カードを作ります。語句「\(term)」について、次の4行だけを出力してください。前置きや説明は付けないでください。
        EN: <英語の語句>
        JA: <日本語の短い訳(1〜3語程度)>
        EX: <英語の語句を使った、短く自然な英語の例文。下の文とは別の文>
        EXJA: <その例文の日本語訳>
        語句が英語なら EN はその語句をそのまま書き、語句が日本語なら JA はその語句をそのまま書いてください。
        訳は下の文での意味に合わせてください。
        文: \(context.isEmpty ? "(なし)" : String(context.prefix(500)))
        """
    }

    public struct CardContent: Equatable, Sendable {
        public var english: String
        public var japanese: String
        public var example: String
        public var exampleTranslation: String
    }

    public static func parseCardPair(_ raw: String) -> CardContent? {
        var fields: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            fields[key] = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let english = fields["EN"], !english.isEmpty,
              let japanese = fields["JA"], !japanese.isEmpty
        else { return nil }
        return CardContent(
            english: english,
            japanese: japanese,
            example: fields["EX"] ?? "",
            exampleTranslation: fields["EXJA"] ?? ""
        )
    }
}
