import Foundation

// ChatGPT などの音声通話に貼って、英語のレッスンをしてもらうための学習状況のまとめ。
// 単語帳は全部、テストの記録は最近の分だけ入れる
public struct LessonBrief: Sendable {
    public static let recentDays = 30
    public static let missedLimit = 40
    public static let writingLimit = 10

    public var words: [WordEntry]
    public var events: [ActivityEvent]
    public var now: Date

    public init(words: [WordEntry], events: [ActivityEvent], now: Date = .now) {
        self.words = words
        self.events = events
        self.now = now
    }

    public func markdown(calendar: Calendar = .current) -> String {
        let since = calendar.date(byAdding: .day, value: 1 - Self.recentDays, to: calendar.startOfDay(for: now))!
        let recent = events.filter { $0.date >= since }
        var lines = [
            "# My English Learning Data (Gloss)",
            "",
            "You are my English tutor in a voice lesson. I'm a Japanese software engineer learning English used at work.",
            "Use the data below to run the lesson: practice the words I haven't learned yet in short spoken exchanges,",
            "revisit the words and sentences I got wrong, and use my known words naturally. Speak simple English,",
            "correct my mistakes briefly, and switch to Japanese only when I'm stuck.",
            "Ask one question at a time and wait for my answer. Don't read the lists aloud.",
            "",
            "## Summary",
            "",
            "- Date: \(Self.dateText(now, calendar: calendar))",
            "- Study streak: \(events.streak(until: now, calendar: calendar)) days (study days in total: \(ProgressSeries.studyDays(events, calendar: calendar)))",
            "- Points: \(Points.total(events))",
            "- Words in my Book: \(words.count) (Known \(count(.known)), Unsure \(count(.unsure)), Not Yet \(count(.notYet)))",
        ]
        let quizTotal = recent.filter { ActivityKind.wordTests.contains($0.kind) }.compactMap(\.total).reduce(0, +)
        if quizTotal > 0 {
            let correct = recent.filter { ActivityKind.wordTests.contains($0.kind) }.compactMap(\.score).reduce(0, +)
            lines.append("- Word Test, last \(Self.recentDays) days: \(correct) / \(quizTotal) correct")
        }
        let englishTotal = recent.filter { $0.kind == .glossRead }.compactMap(\.total).reduce(0, +)
        if englishTotal > 0 {
            let english = recent.filter { $0.kind == .glossRead }.compactMap(\.score).reduce(0, +)
            lines.append("- English left in my translations, last \(Self.recentDays) days: \(english * 100 / englishTotal)%")
        }

        for mastery in [Mastery.notYet, .unsure, .known] {
            let entries = words.filter { $0.masteryLevel == mastery }.sorted(by: Self.newestFirst)
            guard !entries.isEmpty else { continue }
            lines += ["", "## Words: \(mastery.label) (\(entries.count))", ""]
            lines += entries.map(Self.line)
        }

        let missed = recent
            .filter { ActivityKind.wordTests.contains($0.kind) }
            .sorted(by: Self.newestFirst)
            .flatMap { $0.answers ?? [] }
            .filter { $0.verdict != .known }
            .prefix(Self.missedLimit)
        if !missed.isEmpty {
            lines += ["", "## Recent Word Test Mistakes", ""]
            let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            lines += missed.map { answer in
                var line = "- \(Self.flat(answer.prompt)) → my answer: \(answer.answer.isEmpty ? "(blank)" : Self.flat(answer.answer))"
                if let word = byID[answer.wordID] { line += " (correct: \(Self.pair(word)))" }
                return line
            }
        }

        let writings = recent
            .filter { $0.kind == .writing || $0.kind == .reading }
            .sorted(by: Self.newestFirst)
            .prefix(Self.writingLimit)
        if !writings.isEmpty {
            lines += ["", "## Recent Writing / Reading Tests", ""]
            for event in writings {
                lines.append("- \(event.kind.label): \(Self.flat(event.title)) (\(event.score ?? 0) pts)")
                if let answer = event.answer, !answer.isEmpty { lines.append("  - My answer: \(Self.flat(answer))") }
                if let detail = event.detail, !detail.isEmpty { lines.append("  - Corrected: \(Self.flat(detail))") }
            }
        }
        return lines.joined(separator: "\n")
    }

    // スマホの Web アプリと同じ 2026-10-11 の形にする
    static func dateText(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func count(_ mastery: Mastery) -> Int {
        words.filter { $0.masteryLevel == mastery }.count
    }

    // 「英語 — 日本語 (例文)」の1行にする
    static func line(_ entry: WordEntry) -> String {
        var line = "- \(pair(entry))"
        if let example = entry.example, !example.isEmpty { line += " (e.g. \(flat(example)))" }
        return line
    }

    // カードの訳がまだ無い単語は、保存したときの説明の空でない1行目を、80文字まで使う。
    // Web と同じ数え方にするため、文字は Unicode のコードポイントで数える
    static func pair(_ entry: WordEntry) -> String {
        let rawEnglish = entry.english ?? entry.term
        let english = flat(rawEnglish)
        let firstLine = entry.note.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let note = String(String.UnicodeScalarView(firstLine.unicodeScalars.prefix(80)))
        let meaning = flat(entry.japanese ?? (entry.term == rawEnglish ? note : entry.term))
        return meaning.isEmpty ? english : "\(english) — \(meaning)"
    }

    // 複数行の答えや添削で箇条書きが崩れないよう、改行を「 / 」にして1行にする
    static func flat(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    // 新しい順。同じ時刻なら id で決めて、Mac と Web で並びを揃える
    static func newestFirst<T: Identifiable<UUID>>(_ a: T, _ b: T) -> Bool where T: LessonDated {
        let (x, y) = (a.lessonSeconds, b.lessonSeconds)
        return x != y ? x > y : a.id.uuidString < b.id.uuidString
    }
}

// 同期では秒より細かい時刻が落ちるので、並べるときは秒で比べる
protocol LessonDated {
    var date: Date { get }
}

extension LessonDated {
    var lessonSeconds: Int { Int(date.timeIntervalSince1970.rounded(.down)) }
}

extension WordEntry: LessonDated {}
extension ActivityEvent: LessonDated {}
