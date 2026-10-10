import GlossCore
import SwiftUI

// 今日やったことを全部ここにまとめる。進んでいる実感が続けるいちばんの燃料なので、数字を大きく出す
struct ReportToday: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(WordsStore.self) private var words

    var body: some View {
        let report = activity.report()
        VStack(alignment: .leading, spacing: 24) {
            TodayHeader(report: report, streak: activity.state.events.streak(until: .now))
            StatGrid(report: report, totalWords: words.state.words.count)
            if report.isEmpty {
                ContentUnavailableView(
                    "Nothing yet today",
                    systemImage: "sun.max",
                    description: Text("Translate, flip cards, or take a challenge, and it shows up here.")
                )
                .frame(minHeight: 160)
            } else {
                Timeline(events: report.events)
            }
        }
    }
}

private struct TodayHeader: View {
    let report: DayReport
    let streak: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(report.day, format: .dateTime.month().day().weekday())
                .font(.largeTitle.weight(.bold))
            Spacer()
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct StatGrid: View {
    let report: DayReport
    let totalWords: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(value: "\(report.count(.translated))", unit: "", label: "Translations", symbol: "character.bubble")
            StatTile(value: "\(report.count(.wordSaved))", unit: "", label: "Words Saved", caption: "\(totalWords) in your Book", symbol: "bookmark")
            StatTile(value: "\(report.count(.cardFlipped))", unit: "", label: "Cards Flipped", symbol: "rectangle.on.rectangle")
            StatTile(
                value: report.quizTotal == 0 ? "–" : "\(report.quizCorrect * 100 / report.quizTotal)",
                unit: report.quizTotal == 0 ? "" : "%",
                label: "Word Tests",
                caption: report.quizTotal == 0 ? nil : "\(report.quizCorrect) / \(report.quizTotal) correct",
                symbol: "character.textbox"
            )
            StatTile(
                value: report.writingAverage.map(String.init) ?? "–",
                unit: report.writingAverage == nil ? "" : "pts",
                label: "Writing Test",
                caption: report.writingAverage == nil ? nil : "average of \(report.count(.writing))",
                symbol: "pencil.and.list.clipboard"
            )
            StatTile(
                value: report.readingAverage.map(String.init) ?? "–",
                unit: report.readingAverage == nil ? "" : "pts",
                label: "Reading Test",
                caption: report.readingAverage == nil ? nil : "average of \(report.count(.reading))",
                symbol: "text.magnifyingglass"
            )
        }
    }
}

private struct StatTile: View {
    let value: String
    let unit: String
    let label: String
    var caption: String?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(unit).foregroundStyle(.secondary)
            }
            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

private struct Timeline: View {
    let events: [ActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's Log").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(events) { event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(event.date, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .leading)
                    Image(systemName: event.kind.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).lineLimit(2)
                        if let detail = event.detail {
                            Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if let result = event.resultText {
                        Text(result).font(.callout.weight(.semibold)).monospacedDigit()
                    }
                }
                .padding(.vertical, 7)
                Divider()
            }
        }
    }
}

extension ActivityKind {
    var symbol: String {
        switch self {
        case .translated: "character.bubble"
        case .wordSaved: "bookmark"
        case .cardFlipped: "rectangle.on.rectangle"
        case .wordQuiz: "character.textbox"
        case .meaningQuiz: "character.book.closed"
        case .writing: "pencil.and.list.clipboard"
        case .reading: "text.magnifyingglass"
        }
    }
}

extension ActivityEvent {
    var resultText: String? {
        switch kind {
        case .wordQuiz, .meaningQuiz: score.flatMap { s in total.map { "\(s) / \($0)" } }
        case .writing, .reading: score.map { "\($0) pts" }
        default: nil
        }
    }
}
