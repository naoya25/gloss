import Foundation

public enum ReportRange: String, CaseIterable, Identifiable, Sendable {
    case twoWeeks
    case month
    case quarter
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .twoWeeks: "2W"
        case .month: "1M"
        case .quarter: "3M"
        case .all: "All"
        }
    }

    // All は、いちばん古い記録の日から
    public func days(since earliest: Date?, until day: Date, calendar: Calendar = .current) -> Int {
        switch self {
        case .twoWeeks: return 14
        case .month: return 30
        case .quarter: return 90
        case .all:
            guard let earliest else { return 14 }
            let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: day)).day ?? 0
            return max(span + 1, 14)
        }
    }
}

public struct DailyValue: Equatable, Sendable {
    public var day: Date
    public var value: Double
}

public struct DailyKindCount: Hashable, Sendable {
    public var day: Date
    public var kind: ActivityKind
    public var count: Int
}

public enum ProgressSeries {
    static func dayList(_ count: Int, until day: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: day)
        return (0..<count).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
    }

    public static func activity(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyKindCount] {
        let days = dayList(count, until: day, calendar: calendar)
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return days.flatMap { date in
            let dayEvents = grouped[date] ?? []
            return ActivityKind.allCases.compactMap { kind in
                let n = dayEvents.filter { $0.kind == kind }.count
                return n == 0 ? nil : DailyKindCount(day: date, kind: kind, count: n)
            }
        }
    }

    // 単語帳の語数を、追加した日で積み上げる。今ある単語だけで数えるので、消した単語は入らない
    public static func bookSize(_ words: [WordEntry], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        let added = words.map { calendar.startOfDay(for: $0.date) }.sorted()
        var index = 0
        return dayList(count, until: day, calendar: calendar).map { date in
            while index < added.count, added[index] <= date { index += 1 }
            return DailyValue(day: date, value: Double(index))
        }
    }

    public static func quizAccuracy(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        dailyAggregate(events.filter { ActivityKind.wordTests.contains($0.kind) }, days: count, until: day, calendar: calendar) { dayEvents in
            let total = dayEvents.compactMap(\.total).reduce(0, +)
            guard total > 0 else { return nil }
            return Double(dayEvents.compactMap(\.score).reduce(0, +)) * 100 / Double(total)
        }
    }

    public static func averageScore(_ events: [ActivityEvent], kind: ActivityKind, days count: Int, until day: Date, calendar: Calendar = .current) -> [DailyValue] {
        dailyAggregate(events.filter { $0.kind == kind }, days: count, until: day, calendar: calendar) { dayEvents in
            let scores = dayEvents.compactMap(\.score)
            return scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        }
    }

    static func dailyAggregate(_ events: [ActivityEvent], days count: Int, until day: Date, calendar: Calendar, value: ([ActivityEvent]) -> Double?) -> [DailyValue] {
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return dayList(count, until: day, calendar: calendar).compactMap { date in
            grouped[date].flatMap(value).map { DailyValue(day: date, value: $0) }
        }
    }

    public static func longestStreak(_ events: [ActivityEvent], calendar: Calendar = .current) -> Int {
        let days = Set(events.map { calendar.startOfDay(for: $0.date) }).sorted()
        var longest = 0
        var current = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    public static func studyDays(_ events: [ActivityEvent], calendar: Calendar = .current) -> Int {
        Set(events.map { calendar.startOfDay(for: $0.date) }).count
    }
}
