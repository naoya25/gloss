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
    case recommended
    case stale
    case fewestFlips
    case mastery
    case newest
    case alphabetical
    case random

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .recommended: "Recommended"
        case .stale: "Least Recently Seen"
        case .fewestFlips: "Fewest Flips"
        case .mastery: "Least Known"
        case .newest: "Newest"
        case .alphabetical: "A to Z"
        case .random: "Random"
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

    // Book の検索。英語・日本語・説明・例文のどこかに含まれていれば当たり。大文字小文字と全角半角の違いは無視する
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [term, english, japanese, note, context, example, exampleTranslation]
            .compactMap { $0 }
            .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
    }

    public mutating func recordFlip(at date: Date = Date()) {
        flips = flipCount + 1
        lastReviewed = date
    }
}

extension Array where Element == WordEntry {
    // recommended は、テストの記録(events)も合わせて、忘れていそうな順に並べる
    public func sorted(by order: WordSort, events: [ActivityEvent] = [], now: Date = .now) -> [WordEntry] {
        if order == .random { return shuffled() }
        if order == .recommended {
            let streaks = Recall.streaks(events)
            let scored = map { ($0, Recall.forgetting($0, streak: streaks[$0.id] ?? 0, now: now)) }
            return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.date > $1.0.date }.map(\.0)
        }
        // 同じ値どうしは追加が新しい順にして、並びが毎回ぶれないようにする
        return sorted { a, b in
            switch order {
            case .stale:
                let left = a.lastReviewed ?? .distantPast
                let right = b.lastReviewed ?? .distantPast
                if left != right { return left < right }
            case .fewestFlips:
                if a.flipCount != b.flipCount { return a.flipCount < b.flipCount }
            case .mastery:
                if a.masteryLevel != b.masteryLevel { return a.masteryLevel.rawValue < b.masteryLevel.rawValue }
            case .alphabetical:
                let order = a.text(for: .english).localizedCaseInsensitiveCompare(b.text(for: .english))
                if order != .orderedSame { return order == .orderedAscending }
            case .newest, .random, .recommended:
                break
            }
            return a.date > b.date
        }
    }
}

// 忘れていそうな度合いを、忘却曲線(思い出せる見込み = e^(-経過日数 / 記憶の持ち))で見積もる。
// 記憶の持ちは、印ごとの日数(✕ 0.5・? 2・✓ 7)を、テストで続けて正解した回数だけ倍にしたもの
public enum Recall {
    // 語ごとに、直近から続けて正解した回数。書くテストは 1、4択は見て分かっただけなので 0.5 と数え、外したら途切れる
    public static func streaks(_ events: [ActivityEvent]) -> [UUID: Double] {
        var streaks: [UUID: Double] = [:]
        var broken: Set<UUID> = []
        for event in events.sorted(by: { $0.date > $1.date }) where ActivityKind.wordTests.contains(event.kind) {
            for answer in event.answers ?? [] where !broken.contains(answer.wordID) {
                if answer.verdict == .known {
                    streaks[answer.wordID, default: 0] += event.isChoiceTest ? 0.5 : 1
                } else {
                    broken.insert(answer.wordID)
                }
            }
        }
        return streaks
    }

    // 0(覚えている)〜 1(忘れていそう)。一度も見ていない単語は、追加した日から数える
    public static func forgetting(_ word: WordEntry, streak: Double, now: Date) -> Double {
        let base: Double = switch word.masteryLevel {
        case .notYet: 0.5
        case .unsure: 2
        case .known: 7
        }
        let stability = base * pow(2, min(streak, 4))
        let days = max(0, now.timeIntervalSince(word.lastReviewed ?? word.date) / 86_400)
        return 1 - exp(-days / stability)
    }
}
