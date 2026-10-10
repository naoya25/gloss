import Foundation

public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    public static let wordTests: Set<ActivityKind> = [.wordQuiz, .meaningQuiz]

    case translated
    case wordSaved
    case cardFlipped
    case wordQuiz
    case meaningQuiz
    case writing
    case reading

    public var label: String {
        switch self {
        case .translated: "Translated"
        case .wordSaved: "Saved a word"
        case .cardFlipped: "Flipped a card"
        case .wordQuiz: "Word Test"
        case .meaningQuiz: "Meaning Test"
        case .writing: "Writing Test"
        case .reading: "Reading Test"
        }
    }
}

// 単語テストの1問ぶんの記録
public struct WordAnswer: Codable, Hashable, Sendable {
    public var wordID: UUID
    public var prompt: String
    public var answer: String
    public var verdict: Mastery

    public init(wordID: UUID, prompt: String, answer: String, verdict: Mastery) {
        self.wordID = wordID
        self.prompt = prompt
        self.answer = answer
        self.verdict = verdict
    }
}

// 学習の操作を1件ずつ残す。何をやったかはこの記録だけを正とし、Report もここから数える。
// 一度書いたら書き換えない
public struct ActivityEvent: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var kind: ActivityKind
    public var title: String
    public var score: Int?
    public var total: Int?
    public var detail: String?
    // 単語を保存した・めくったときの、その単語
    public var wordID: UUID?
    // 英作・英文訳テストで自分が書いた答え
    public var answer: String?
    // 単語テストの1問ずつの答えと判定
    public var answers: [WordAnswer]?

    public init(
        kind: ActivityKind, title: String, score: Int? = nil, total: Int? = nil, detail: String? = nil,
        wordID: UUID? = nil, answer: String? = nil, answers: [WordAnswer]? = nil, date: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.score = score
        self.total = total
        self.detail = detail
        self.wordID = wordID
        self.answer = answer
        self.answers = answers
        self.date = date
    }
}

public struct DayReport: Equatable, Sendable {
    public var day: Date
    public var events: [ActivityEvent]

    public init(events: [ActivityEvent], on day: Date, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day)
        self.events = events
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    public func count(_ kind: ActivityKind) -> Int {
        events.filter { $0.kind == kind }.count
    }

    // 単語テストは向きに関わらず、1回ごとの正解数と問題数を足し合わせて正答率にする
    public var quizCorrect: Int { events.filter { ActivityKind.wordTests.contains($0.kind) }.compactMap(\.score).reduce(0, +) }
    public var quizTotal: Int { events.filter { ActivityKind.wordTests.contains($0.kind) }.compactMap(\.total).reduce(0, +) }

    public var writingAverage: Int? { average(.writing) }
    public var readingAverage: Int? { average(.reading) }

    public func average(_ kind: ActivityKind) -> Int? {
        let scores = events.filter { $0.kind == kind }.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    public var isEmpty: Bool { events.isEmpty }

    public func markdown(calendar: Calendar = .current) -> String {
        var lines = ["# Study Report: \(day.formatted(.dateTime.year().month().day().weekday()))", ""]
        lines.append("- Translations: \(count(.translated))")
        lines.append("- Words saved: \(count(.wordSaved))")
        lines.append("- Cards flipped: \(count(.cardFlipped))")
        if quizTotal > 0 { lines.append("- Word Test: \(quizCorrect) / \(quizTotal) correct") }
        if let average = writingAverage { lines.append("- Writing Test: \(count(.writing)) tasks, average \(average) pts") }
        if let average = readingAverage { lines.append("- Reading Test: \(count(.reading)) tasks, average \(average) pts") }
        let saved = events.filter { $0.kind == .wordSaved }.map(\.title)
        if !saved.isEmpty {
            lines += ["", "## Words Saved", ""] + saved.reversed().map { "- \($0)" }
        }
        let writings = events.filter { $0.kind == .writing }
        if !writings.isEmpty {
            lines += ["", "## Writing Test", ""]
            for event in writings.reversed() {
                lines.append("- \(event.title) (\(event.score ?? 0) pts)")
                if let detail = event.detail { lines.append("  - \(detail)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension Array where Element == ActivityEvent {
    // 何日続けて学習しているか。今日まだ何もしていなければ、昨日までで数える
    public func streak(until day: Date, calendar: Calendar = .current) -> Int {
        let days = Set(map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: day)
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
