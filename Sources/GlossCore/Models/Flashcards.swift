import Foundation

public enum Mastery: Int, Codable, CaseIterable, Identifiable, Sendable {
    case notYet = 0
    case unsure = 1
    case known = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .notYet: "Not Yet"
        case .unsure: "Unsure"
        case .known: "Known"
        }
    }
}

public enum CardFace: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case japanese

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .english: "English"
        case .japanese: "Japanese"
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
        case .stale: "Least Recently Seen"
        case .fewestFlips: "Fewest Flips"
        case .mastery: "Least Known"
        case .newest: "Newest"
        }
    }
}

extension WordEntry {
    public var flipCount: Int { flips ?? 0 }
    public var masteryLevel: Mastery { mastery ?? .notYet }
    public var hasCardPair: Bool { !(english ?? "").isEmpty && !(japanese ?? "").isEmpty }
    // 訳と例文がそろったら、もう AI に作らせない
    public var isCardComplete: Bool { hasCardPair && !(example ?? "").isEmpty && !(exampleTranslation ?? "").isEmpty }

    public func needsCardContent(for engine: Engine) -> Bool {
        !isCardComplete && cardError == nil && self.engine == engine
    }

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
