import Charts
import GlossCore
import SwiftUI

// 進んでいる実感が続けるいちばんの燃料なので、やった量より先に、できるようになったことを大きく出す
struct ReportOverview: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(WordsStore.self) private var words
    @State private var range: ReportRange = .twoWeeks
    // Slack に貼る画像として描くときは、押せる部品を外して2週間分で固定する
    var isSnapshot = false

    var body: some View {
        let events = activity.state.events
        let report = activity.report()
        let said = Growth.distinct(Growth.firstCorrect(events, choice: false), words: words.state.words)
        let seen = Growth.distinct(Growth.firstCorrect(events, choice: true), words: words.state.words)
        let earliest = events.map(\.date).min()
        let days = Self.visibleDays((isSnapshot ? .twoWeeks : range).days(since: earliest, until: .now), since: earliest)
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.day, format: .dateTime.month().day().weekday())
                    .font(.largeTitle.weight(.bold))
                Spacer()
                let streak = events.streak(until: .now)
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.headline)
                        .symbolRenderingMode(.multicolor)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                EnglishHero(report: report, latest: Growth.latestEnglish(events))
                WordsHero(said: said, seen: seen)
                    .frame(maxWidth: 300)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Progress").font(.title2.weight(.bold))
                    Spacer()
                    if isSnapshot {
                        Text("Last 2 weeks").foregroundStyle(.secondary)
                    } else {
                        Picker("Range", selection: $range) {
                            ForEach(ReportRange.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                let english = ProgressSeries.englishRate(events, days: days, until: .now)
                GrowthCard(title: "Read in English", claim: "How much of each translation stayed in English. The higher, the less you need translation.") {
                    if english.isEmpty {
                        EmptyChart(text: "Translate English and choose “Read It As Is” to see this grow.")
                    } else {
                        EnglishChart(data: english, domain: Self.domain(days: days))
                    }
                }
                GrowthCard(title: "Words you can say", claim: "Words you got right in a test for the first time, added up.") {
                    if said.isEmpty && seen.isEmpty {
                        EmptyChart(text: "Take a test to see this grow.")
                    } else {
                        WordsChart(
                            said: Growth.cumulative(said, days: days, until: .now),
                            seen: Growth.cumulative(seen, days: days, until: .now),
                            domain: Self.domain(days: days)
                        )
                    }
                }
                TestsCard(events: events, days: days, domain: Self.domain(days: days))
                GrowthCard(title: "Study days", claim: "The days you studied, and how much. Darker means more.") {
                    let weeks = StudyCalendar.weeks(since: earliest)
                    StudyCalendar(weeks: weeks, counts: Growth.dailyCounts(events, days: weeks * 7, until: .now))
                }
            }
            SaidToday(ids: Growth.newlyCorrect(said, on: .now))
            TodayCounts(report: report, totalPoints: Points.total(events))
        }
    }
}

extension ReportOverview {
    // 始めたばかりで記録が期間より短いときは、始めた日から見せる(最短 7 日)。そうしないとグラフの大半が空になる
    static func visibleDays(_ days: Int, since earliest: Date?) -> Int {
        guard let earliest else { return days }
        let calendar = Calendar.current
        let span = (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: .now)).day ?? 0) + 1
        return min(days, max(7, span))
    }

    // 1日しか記録が無くても、横軸は選んだ期間の日付にする。そうしないと1日の中の時刻が軸に出る
    static func domain(days: Int) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: 1 - days, to: today)!
        return start...calendar.date(byAdding: .hour, value: 12, to: today)!
    }
}

enum GrowthStyle {
    // 目盛りの線は細い実線にして、データより目立たせない(点線は雑音になる)
    static let grid = StrokeStyle(lineWidth: 0.5)
}

enum GrowthColor {
    // 英語は青。4択で分かった語は、青と色覚の型を問わず見分けられる橙(dataviz の検査で確認済み)
    static let english = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let seen = Color(red: 0.76, green: 0.48, blue: 0.17)
}

private struct GrowthCard<Content: View>: View {
    let title: String
    let claim: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(claim).font(.callout).foregroundStyle(.secondary)
            content
                .frame(height: 170)
                .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

private struct EmptyChart: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HeroCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

private struct HeroNumber: View {
    let value: String
    var unit = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(unit).font(.title.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

// 訳の中の英語と日本語の割合を横棒で見せる。青が伸びていくのが Gloss の進み方
private struct EnglishHero: View {
    let report: DayReport
    let latest: (day: Date, rate: Int)?

    var body: some View {
        HeroCard(label: "Read in English") {
            if let rate = report.englishRate {
                HeroNumber(value: "\(rate)", unit: "%")
                Text("How much of today's translations stayed in English · \(report.count(.glossRead)) texts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                let english = report.englishCharacters
                let total = max(report.translatedCharacters, 1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule()
                            .fill(GrowthColor.english)
                            .frame(width: max(6, proxy.size.width * CGFloat(english) / CGFloat(total)))
                    }
                }
                .frame(height: 12)
                .padding(.top, 8)
                HStack {
                    Text("English \(english) chars")
                    Spacer()
                    Text("Japanese \(report.translatedCharacters - english) chars")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let latest {
                HeroNumber(value: "\(latest.rate)", unit: "%")
                    .foregroundStyle(.secondary)
                Text("On \(latest.day.formatted(.dateTime.month().day())), the last day you read in English. Nothing yet today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HeroNumber(value: "–")
                Text("Translate English and choose “Read It As Is” to start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WordsHero: View {
    let said: [UUID: Date]
    let seen: [UUID: Date]

    var body: some View {
        let today = Growth.newlyCorrect(said, on: .now).count
        let seenOnly = seen.keys.filter { said[$0] == nil }.count
        HeroCard(label: "Words you can say") {
            HeroNumber(value: "\(said.count)")
            (Text(today > 0 ? "+\(today) today" : "None new today").fontWeight(.semibold).foregroundStyle(.primary)
                + Text(" · words you answered yourself in Word and Meaning Tests").foregroundStyle(.secondary))
                .font(.callout)
            Text("Another \(seenOnly) recognized in 4-Choice Tests")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EnglishChart: View {
    let data: [DailyValue]
    let domain: ClosedRange<Date>
    @State private var selected: Date?

    var body: some View {
        let top = max(10, ((data.map(\.value).max() ?? 0) / 5).rounded(.up) * 5)
        Chart {
            ForEach(data, id: \.day) { item in
                AreaMark(x: .value("Day", item.day, unit: .day), y: .value("English", item.value))
                    .foregroundStyle(GrowthColor.english.opacity(0.12))
                LineMark(x: .value("Day", item.day, unit: .day), y: .value("English", item.value))
                    .foregroundStyle(GrowthColor.english)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Day", item.day, unit: .day), y: .value("English", item.value))
                    .foregroundStyle(GrowthColor.english)
                    .symbolSize(30)
            }
            if let selected, let item = data.min(by: { abs($0.day.timeIntervalSince(selected)) < abs($1.day.timeIntervalSince(selected)) }) {
                RuleMark(x: .value("Day", item.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartTip(title: item.day.formatted(.dateTime.month().day()), value: "\(Int(item.value.rounded()))%")
                    }
            }
        }
        .chartYScale(domain: 0...top)
        .chartXScale(domain: domain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        } }
        .chartYAxis { AxisMarks(values: .stride(by: 5)) { value in
            AxisGridLine(stroke: GrowthStyle.grid)
            AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
        } }
        .chartXSelection(value: $selected)
    }
}

private struct WordsChart: View {
    let said: [DailyValue]
    let seen: [DailyValue]
    let domain: ClosedRange<Date>
    @State private var selected: Date?

    var body: some View {
        let series = [("Said yourself", said, GrowthColor.english), ("4-Choice", seen, GrowthColor.seen)]
        Chart {
            ForEach(series, id: \.0) { name, values, _ in
                ForEach(values, id: \.day) { item in
                    LineMark(x: .value("Day", item.day, unit: .day), y: .value("Words", item.value))
                        .foregroundStyle(by: .value("Test", name))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let last = values.last {
                    PointMark(x: .value("Day", last.day, unit: .day), y: .value("Words", last.value))
                        .foregroundStyle(by: .value("Test", name))
                        .annotation(position: .trailing) {
                            Text("\(Int(last.value))").font(.caption.weight(.semibold))
                        }
                }
            }
            if let selected, let index = said.indices.min(by: { abs(said[$0].day.timeIntervalSince(selected)) < abs(said[$1].day.timeIntervalSince(selected)) }) {
                RuleMark(x: .value("Day", said[index].day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartTip(
                            title: said[index].day.formatted(.dateTime.month().day()),
                            value: "Said \(Int(said[index].value)) · 4-Choice \(Int(seen[index].value))"
                        )
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.0), range: series.map(\.2))
        .chartXScale(domain: domain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        } }
        // 線の右端に数字を直接書くので、目盛りは左に置いて重ならないようにする
        .chartYAxis { AxisMarks(position: .leading) { _ in
            AxisGridLine(stroke: GrowthStyle.grid)
            AxisValueLabel()
        } }
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $selected)
    }
}

// テストごとに1つのグラフ。棒がその日にやった回数(右の目盛り)、線がその日の成績(左の目盛り、0〜100)。
// 回数と成績は単位が違うので、目盛りを左右に分けて両方に書く
private struct TestsCard: View {
    let events: [ActivityEvent]
    let days: Int
    let domain: ClosedRange<Date>

    var body: some View {
        let since = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: .now))!
        let recent = events.filter { $0.date >= since }
        let counts = TestTrend.allCases.map { $0.counts(events, days: days, until: .now) }
        let maxCount = max(1, counts.flatMap { $0.map(\.value) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Tests").font(.headline)
            Text("Bars: how many times you took it that day (right scale). Line: how you did that day (left scale) — share correct for word tests, average score for Writing and Reading.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(TestTrend.allCases.enumerated()), id: \.offset) { index, test in
                    let value = test.value(of: recent)
                    let count = test.count(events, since: since)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(test.label).font(.body.weight(.semibold))
                            Spacer()
                            Text(value.map { "\(count)× · \(Int($0.rounded()))\(test.unit == "%" ? "%" : " pts")" } ?? "Not taken yet")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        // 日付の目盛りは一番下の行だけに書く。5行とも同じ日付なので
                        let isLast = index == TestTrend.allCases.count - 1
                        TestComboChart(
                            counts: counts[index],
                            results: test.series(events, days: days, until: .now),
                            domain: domain,
                            top: maxCount,
                            unit: test.unit,
                            showsDates: isLast
                        )
                        .frame(height: isLast ? 92 : 72)
                    }
                }
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

// 回数は 0〜top を 0〜100 に縮めて同じ枠に描き、右の目盛りで元の回数に読み替える。どのテストも同じ top にして、回数を比べられるようにする
private struct TestComboChart: View {
    let counts: [DailyValue]
    let results: [DailyValue]
    let domain: ClosedRange<Date>
    let top: Double
    let unit: String
    let showsDates: Bool
    @State private var selected: Date?

    var body: some View {
        let done = counts.filter { $0.value > 0 }
        Chart {
            ForEach(done, id: \.day) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Times", item.value / top * 100))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .cornerRadius(2)
            }
            ForEach(results, id: \.day) { item in
                LineMark(x: .value("Day", item.day, unit: .day), y: .value("Result", item.value))
                    .foregroundStyle(GrowthColor.english)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Day", item.day, unit: .day), y: .value("Result", item.value))
                    .foregroundStyle(GrowthColor.english)
                    .symbolSize(24)
            }
            if let selected, let day = (done.map(\.day) + results.map(\.day)).min(by: { abs($0.timeIntervalSince(selected)) < abs($1.timeIntervalSince(selected)) }) {
                let times = Int(done.first { $0.day == day }?.value ?? 0)
                let result = results.first { $0.day == day }?.value
                RuleMark(x: .value("Day", day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartTip(
                            title: day.formatted(.dateTime.month().day()),
                            value: "\(times)× · " + (result.map { "\(Int($0.rounded()))\(unit == "%" ? "%" : " pts")" } ?? "–")
                        )
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: domain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            if showsDates { AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) }
        } }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: GrowthStyle.grid)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)\(unit == "%" ? "%" : "")") }
            }
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisValueLabel { Text("\(Int(((value.as(Double.self) ?? 0) / 100 * top).rounded()))×").foregroundStyle(.tertiary) }
            }
        }
        .chartXSelection(value: $selected)
    }
}

private struct ChartTip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

// やった日のカレンダー。列が週、行が曜日。濃さは記録の数を5段にしたもの(一つの色の濃さだけで量を表す)
private struct StudyCalendar: View {
    let weeks: Int
    let counts: [DailyValue]

    // 始めた週から今週まで。空の週ばかりが並ばないよう、最初のうちは8週だけ見せ、多くても26週まで
    static func weeks(since earliest: Date?) -> Int {
        guard let earliest else { return 8 }
        let days = Calendar.current.dateComponents([.day], from: earliest, to: .now).day ?? 0
        return min(26, max(8, days / 7 + 2))
    }

    var body: some View {
        let calendar = Calendar.current
        let byDay = Dictionary(uniqueKeysWithValues: counts.map { ($0.day, $0.value) })
        let today = calendar.startOfDay(for: .now)
        let lastSunday = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: lastSunday)!
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!
                            let count = Int(byDay[day] ?? 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day > today ? Color.clear : Self.color(for: count))
                                .frame(width: 18, height: 18)
                                .help(day > today ? "" : "\(day.formatted(.dateTime.month().day())): \(count == 0 ? "no study" : "\(count) records")")
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(level: level)).frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    static func color(for count: Int) -> Color {
        color(level: count == 0 ? 0 : count < 30 ? 1 : count < 60 ? 2 : count < 100 ? 3 : 4)
    }

    static func color(level: Int) -> Color {
        level == 0 ? Color.secondary.opacity(0.15) : GrowthColor.english.opacity([0, 0.3, 0.5, 0.75, 1][level])
    }
}

// 保存した語ではなく、今日テストで初めて自分で答えられた語だけを並べる
private struct SaidToday: View {
    @Environment(WordsStore.self) private var words
    let ids: [UUID]

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: words.state.words.map { ($0.id, $0) })
        let entries = ids.compactMap { byID[$0] }
        VStack(alignment: .leading, spacing: 4) {
            Text("Words you said today").font(.title2.weight(.bold))
            Text("Words you got right for the first time in a Word or Meaning Test.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("Take a Word Test or a Meaning Test, and the words you get right show up here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            } else {
                // 単語帳の一覧のように、英語と日本語を1行ずつ並べる。枠で囲まず、細い線で区切る
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible(), spacing: 32)], alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(entry.text(for: .english)).font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(entry.text(for: .japanese)).font(.callout).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// やった量は小さく1行に。消すと、続けた手応えも消えるので残す
private struct TodayCounts: View {
    let report: DayReport
    let totalPoints: Int

    var body: some View {
        let tests = report.events.filter { ActivityKind.wordTests.contains($0.kind) }.count
        let items: [(String, Int)] = [
            ("Translated", report.count(.translated)),
            ("Cards flipped", report.count(.cardFlipped)),
            ("Words saved", report.count(.wordSaved)),
            ("Word tests", tests),
            ("Writing", report.count(.writing)),
            ("Points", report.points),
        ]
        HStack(spacing: 18) {
            Text("Today").font(.callout.weight(.semibold))
            ForEach(items, id: \.0) { label, value in
                HStack(spacing: 4) {
                    Text(label).foregroundStyle(.secondary)
                    Text("\(value)").fontWeight(.semibold).monospacedDigit()
                }
            }
            Spacer()
            Text("\(totalPoints) pt in total").foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}
