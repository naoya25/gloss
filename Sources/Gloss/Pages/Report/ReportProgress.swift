import Charts
import GlossCore
import SwiftUI

struct ReportProgress: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(WordsStore.self) private var words
    @State private var range: ReportRange = .month

    var body: some View {
        let events = activity.state.events
        let earliest = (events.map(\.date) + words.state.words.map(\.date)).min()
        let days = range.days(since: earliest, until: .now)
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("Progress").font(.largeTitle.weight(.bold))
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ReportRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Totals(events: events, words: words.state.words)
            ChartCard(title: "Daily Activity", isEmpty: events.isEmpty, emptyText: "Your daily activity will show up here.") {
                ActivityChart(data: ProgressSeries.activity(events, days: days, until: .now))
            }
            ChartCard(title: "Book Size", isEmpty: words.state.words.isEmpty, emptyText: "Save words to watch your Book grow.") {
                BookSizeChart(data: ProgressSeries.bookSize(words.state.words, days: days, until: .now))
            }
            HStack(alignment: .top, spacing: 16) {
                let accuracy = ProgressSeries.quizAccuracy(events, days: days, until: .now)
                ChartCard(title: "Word Test Accuracy", isEmpty: accuracy.isEmpty, emptyText: "Take a Word Test to see your accuracy.") {
                    ScoreChart(data: accuracy, unit: "%", tint: .teal)
                }
                let writing = ProgressSeries.averageScore(events, kind: .writing, days: days, until: .now)
                let reading = ProgressSeries.averageScore(events, kind: .reading, days: days, until: .now)
                ChartCard(title: "Writing & Reading Score", isEmpty: writing.isEmpty && reading.isEmpty, emptyText: "Take a Writing or Reading Test to see your scores.") {
                    ExerciseScoreChart(writing: writing, reading: reading)
                }
            }
            ChartCard(title: "Mastery", isEmpty: words.state.words.isEmpty, emptyText: "Your Book is empty.", height: 64) {
                MasteryBar(words: words.state.words)
            }
        }
    }
}

private struct Totals: View {
    let events: [ActivityEvent]
    let words: [WordEntry]

    var body: some View {
        HStack(spacing: 12) {
            Total(value: ProgressSeries.studyDays(events), label: "Study Days")
            Total(value: events.streak(until: .now), label: "Current Streak")
            Total(value: ProgressSeries.longestStreak(events), label: "Longest Streak")
            Total(value: words.count, label: "Words in Book")
        }
    }
}

private struct Total: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let isEmpty: Bool
    let emptyText: String
    var height: CGFloat = 160
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                content.frame(height: height)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

private struct ActivityChart: View {
    let data: [DailyKindCount]

    var body: some View {
        Chart(data, id: \.self) { item in
            BarMark(x: .value("Day", item.day, unit: .day), y: .value("Count", item.count))
                .foregroundStyle(by: .value("Kind", item.kind.label))
        }
        .chartForegroundStyleScale(domain: ActivityKind.allCases.map(\.label), range: ActivityKind.allCases.map(\.tint))
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

private struct BookSizeChart: View {
    let data: [DailyValue]

    var body: some View {
        Chart(data, id: \.day) { item in
            AreaMark(x: .value("Day", item.day, unit: .day), y: .value("Words", item.value))
                .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Day", item.day, unit: .day), y: .value("Words", item.value))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
        }
    }
}

private struct ScoreChart: View {
    let data: [DailyValue]
    let unit: String
    let tint: Color

    var body: some View {
        Chart(data, id: \.day) { item in
            LineMark(x: .value("Day", item.day, unit: .day), y: .value(unit, item.value))
                .foregroundStyle(tint)
            PointMark(x: .value("Day", item.day, unit: .day), y: .value(unit, item.value))
                .foregroundStyle(tint)
        }
        .chartYScale(domain: 0...100)
    }
}

private struct ExerciseScoreChart: View {
    let writing: [DailyValue]
    let reading: [DailyValue]

    var body: some View {
        let series = [(ActivityKind.writing, writing), (ActivityKind.reading, reading)]
        Chart {
            ForEach(series, id: \.0) { kind, values in
                ForEach(values, id: \.day) { item in
                    LineMark(x: .value("Day", item.day, unit: .day), y: .value("pts", item.value))
                        .foregroundStyle(by: .value("Test", kind.label))
                    PointMark(x: .value("Day", item.day, unit: .day), y: .value("pts", item.value))
                        .foregroundStyle(by: .value("Test", kind.label))
                }
            }
        }
        .chartForegroundStyleScale(domain: [ActivityKind.writing.label, ActivityKind.reading.label], range: [ActivityKind.writing.tint, ActivityKind.reading.tint])
        .chartYScale(domain: 0...100)
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

private struct MasteryBar: View {
    let words: [WordEntry]

    var body: some View {
        let counts = Mastery.allCases.map { level in (level, words.filter { $0.masteryLevel == level }.count) }
        Chart(counts, id: \.0) { level, count in
            BarMark(x: .value("Words", count), stacking: .normalized)
                .foregroundStyle(by: .value("Mastery", level.label))
                .annotation(position: .overlay) {
                    if count > 0 {
                        Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    }
                }
        }
        .chartForegroundStyleScale(domain: Mastery.allCases.map(\.label), range: [Color.red, Color.orange, Color.green])
        .chartXAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

extension ActivityKind {
    var tint: Color {
        switch self {
        case .translated: .gray
        case .wordSaved: .blue
        case .cardFlipped: .cyan
        case .wordQuiz: .teal
        case .meaningQuiz: .mint
        case .writing: .purple
        case .reading: .pink
        }
    }
}
