import Foundation

// Report の主役。やった量ではなく、できるようになったことを数える
public enum Growth {
    // 語ごとに、テストで初めて正解した時刻。4択は「見て分かった」だけなので、書くテストとは分けて数える
    public static func firstCorrect(_ events: [ActivityEvent], choice: Bool) -> [UUID: Date] {
        var firsts: [UUID: Date] = [:]
        for event in events.sorted(by: { $0.date < $1.date })
        where ActivityKind.wordTests.contains(event.kind) && event.isChoiceTest == choice {
            for answer in event.answers ?? [] where answer.verdict == .known && firsts[answer.wordID] == nil {
                firsts[answer.wordID] = event.date
            }
        }
        return firsts
    }

    // Book に同じ英語の単語が2つあるときは、1語として数える(早く正解したほうを残す)
    public static func distinct(_ firsts: [UUID: Date], words: [WordEntry]) -> [UUID: Date] {
        let keys = Dictionary(uniqueKeysWithValues: words.map { ($0.id, WordEntry.key(for: $0.text(for: .english))) })
        var kept: [String: (UUID, Date)] = [:]
        for (id, date) in firsts {
            let key = keys[id] ?? id.uuidString
            if let current = kept[key], current.1 <= date { continue }
            kept[key] = (id, date)
        }
        return Dictionary(uniqueKeysWithValues: kept.values.map { ($0.0, $0.1) })
    }

    // いちばん最近、英語のまま読んだ日と、その日の割合。今日まだ読んでいないときに見せる
    public static func latestEnglish(_ events: [ActivityEvent], calendar: Calendar = .current) -> (day: Date, rate: Int)? {
        guard let last = events.filter({ $0.kind == .glossRead }).max(by: { $0.date < $1.date }) else { return nil }
        let report = DayReport(events: events, on: last.date, calendar: calendar)
        return report.englishRate.map { (report.day, $0) }
    }

    // その日に初めて正解した語。古い順
    public static func newlyCorrect(_ firsts: [UUID: Date], on day: Date, calendar: Calendar = .current) -> [UUID] {
        firsts.filter { calendar.isDate($0.value, inSameDayAs: day) }.sorted { $0.value < $1.value }.map(\.key)
    }

    // 初めて正解した語の、日ごとの累計
    public static func cumulative(_ firsts: [UUID: Date], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        let dates = firsts.values.map { calendar.startOfDay(for: $0) }.sorted()
        var index = 0
        return ProgressSeries.dayList(count, until: day, calendar: calendar).map { date in
            while index < dates.count, dates[index] <= date { index += 1 }
            return DailyValue(day: date, value: Double(index))
        }
    }

    // 日ごとの記録の数。やった日のカレンダーの濃さに使う
    public static func dailyCounts(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return ProgressSeries.dayList(count, until: day, calendar: calendar).map { date in
            DailyValue(day: date, value: Double(grouped[date]?.count ?? 0))
        }
    }

    // Writing Test の点を古い順に。since より前は入れない
    public static func writingScores(_ events: [ActivityEvent], since: Date) -> [Int] {
        events.filter { $0.kind == .writing && $0.date >= since }.sorted { $0.date < $1.date }.compactMap(\.score)
    }

    // 直近 window 回の平均。最初のうちはあるぶんだけで平均する
    public static func movingAverage(_ scores: [Int], window: Int = 5) -> [Double] {
        scores.indices.map { index in
            let slice = scores[max(0, index - window + 1)...index]
            return Double(slice.reduce(0, +)) / Double(slice.count)
        }
    }
}

// テストの種類ごとの推移。単語のテストは正答率、文のテストは点で、どちらも 0〜100
public enum TestTrend: String, CaseIterable, Identifiable, Sendable {
    case choice
    case word
    case meaning
    case writing
    case reading

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .choice: ChoiceQuiz.title
        case .word: ActivityKind.wordQuiz.label
        case .meaning: ActivityKind.meaningQuiz.label
        case .writing: ActivityKind.writing.label
        case .reading: ActivityKind.reading.label
        }
    }

    // 単語のテストは「何問中何問」を足し合わせた正答率、文のテストは点の平均
    public var unit: String { isWordTest ? "%" : "pts" }
    var isWordTest: Bool { self == .choice || self == .word || self == .meaning }

    public func matches(_ event: ActivityEvent) -> Bool {
        switch self {
        case .choice: ActivityKind.wordTests.contains(event.kind) && event.isChoiceTest
        case .word: event.kind == .wordQuiz && !event.isChoiceTest
        case .meaning: event.kind == .meaningQuiz && !event.isChoiceTest
        case .writing: event.kind == .writing
        case .reading: event.kind == .reading
        }
    }

    public func value(of events: [ActivityEvent]) -> Double? {
        let mine = events.filter(matches)
        if isWordTest {
            let total = mine.compactMap(\.total).reduce(0, +)
            return total == 0 ? nil : Double(mine.compactMap(\.score).reduce(0, +)) * 100 / Double(total)
        }
        let scores = mine.compactMap(\.score)
        return scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
    }

    // 日ごとの値。テストをしていない日は入れない
    public func series(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        ProgressSeries.dailyAggregate(events.filter(matches), days: count, until: day, calendar: calendar) { value(of: $0) }
    }

    // 日ごとの回数。やっていない日は 0
    public func counts(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        Growth.dailyCounts(events.filter(matches), days: count, until: day, calendar: calendar)
    }

    public func count(_ events: [ActivityEvent], since: Date) -> Int {
        events.filter { matches($0) && $0.date >= since }.count
    }
}

// Report の画面と同じ並びの Markdown。Slack などに貼る用
public struct GrowthReport: Sendable {
    public static let days = 14

    public var events: [ActivityEvent]
    public var words: [WordEntry]
    public var now: Date

    public init(events: [ActivityEvent], words: [WordEntry], now: Date = .now) {
        self.events = events
        self.words = words
        self.now = now
    }

    public func markdown(calendar: Calendar = .current) -> String {
        let report = DayReport(events: events, on: now, calendar: calendar)
        let said = Growth.distinct(Growth.firstCorrect(events, choice: false), words: words)
        let seen = Growth.distinct(Growth.firstCorrect(events, choice: true), words: words)
        let today = Growth.newlyCorrect(said, on: now, calendar: calendar)
        var lines = ["# Gloss Report: \(LessonBrief.dateText(now, calendar: calendar)) (\(Self.weekday(now, calendar: calendar)))"]
        let streak = events.streak(until: now, calendar: calendar)
        if streak > 0 { lines.append("🔥 \(streak)-day streak") }

        lines += ["", "## Read in English: \(report.englishRate.map { "\($0)%" } ?? "–")"]
        if report.englishRate != nil {
            lines.append("How much of today's translations stayed in English (\(report.count(.glossRead)) texts, \(report.englishCharacters) of \(report.translatedCharacters) chars)")
        } else {
            lines.append("No translations read in English today")
        }
        let trend = ProgressSeries.englishRate(events, days: Self.days, until: now, calendar: calendar)
        if trend.count >= 2 {
            lines.append("Last \(Self.days) days: " + trend.map { "\(Self.monthDay($0.day, calendar: calendar)) \(Int($0.value.rounded()))%" }.joined(separator: " · "))
        }

        let seenOnly = seen.keys.filter { said[$0] == nil }.count
        lines += ["", "## Words you can say: \(said.count)\(today.isEmpty ? "" : " (+\(today.count) today)")"]
        lines.append("Words you answered yourself in Word and Meaning Tests. Another \(seenOnly) recognized in 4-Choice Tests")
        let byID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let entries = today.compactMap { byID[$0] }
        if !entries.isEmpty {
            lines += ["", "### Words you said today", ""]
            lines += entries.map { "- \($0.text(for: .english)) — \($0.text(for: .japanese))" }
        }

        let since = calendar.date(byAdding: .day, value: 1 - Self.days, to: calendar.startOfDay(for: now))!
        let recent = events.filter { $0.date >= since }
        let testLines = TestTrend.allCases.compactMap { test -> String? in
            guard let value = test.value(of: recent) else { return nil }
            return "- \(test.label): \(test.count(events, since: since)) times, \(Int(value.rounded()))\(test.unit == "%" ? "% correct" : " pts on average")"
        }
        if !testLines.isEmpty {
            lines += ["", "## Tests (last \(Self.days) days)"] + testLines
        }

        let tests = report.events.filter { ActivityKind.wordTests.contains($0.kind) }.count
        lines += ["", "## Today", "Translated \(report.count(.translated)) · Cards flipped \(report.count(.cardFlipped)) · Words saved \(report.count(.wordSaved)) · Word tests \(tests) · Writing \(report.count(.writing)) · Points \(report.points) (\(Points.total(events)) in total)"]
        return lines.joined(separator: "\n")
    }

    static func weekday(_ date: Date, calendar: Calendar) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: date) - 1]
    }

    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }
}

extension ActivityEvent {
    public var isChoiceTest: Bool { title == ChoiceQuiz.title }
}
