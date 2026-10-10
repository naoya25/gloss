import AppKit
import GlossCore
import SwiftUI

// Slack などに貼る今日のレポートの画像。中身は Markdown のコピーと同じ。
// 貼り先の地の色が分からないので、システムの色は使わず、明るい色で決め打ちにする
struct ReportShareCard: View {
    let report: DayReport
    let streak: Int

    private static let ink = Color(red: 0.12, green: 0.14, blue: 0.16)
    private static let sub = Color(red: 0.35, green: 0.39, blue: 0.43)
    private static let line = Color(red: 0.82, green: 0.85, blue: 0.88)
    private static let tile = Color(red: 0.96, green: 0.97, blue: 0.98)
    private static let accent = Color(red: 0.18, green: 0.42, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            stats
            if !savedWords.isEmpty { savedSection }
            if !writings.isEmpty { writingSection }
            Text("Gloss")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.sub)
        }
        .padding(32)
        .frame(width: 640, alignment: .leading)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Study Report")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.accent)
                Text(report.day, format: .dateTime.year().month().day().weekday())
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Self.ink)
            }
            Spacer()
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var stats: some View {
        let items: [(String, String)] = [
            ("Translations", "\(report.count(.translated))"),
            ("Words Saved", "\(report.count(.wordSaved))"),
            ("Cards Flipped", "\(report.count(.cardFlipped))"),
            ("Word Tests", report.quizTotal == 0 ? "–" : "\(report.quizCorrect)/\(report.quizTotal)"),
            ("Writing", report.writingAverage.map { "\($0) pts" } ?? "–"),
            ("Reading", report.readingAverage.map { "\($0) pts" } ?? "–"),
        ]
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<2) { row in
                GridRow {
                    ForEach(0..<3) { column in
                        let item = items[row * 3 + column]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Self.sub)
                            Text(item.1)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Self.ink)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Self.tile))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Self.line))
                    }
                }
            }
        }
    }

    private var savedWords: [String] {
        report.events.filter { $0.kind == .wordSaved }.map(\.title).reversed()
    }

    private var writings: [ActivityEvent] {
        report.events.filter { $0.kind == .writing }.reversed()
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Words Saved")
            FlowLayout(spacing: 6) {
                ForEach(savedWords, id: \.self) { word in
                    Text(word)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Self.accent.opacity(0.1)))
                }
            }
        }
    }

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Writing Test")
            ForEach(writings) { event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Self.ink)
                        if let detail = event.detail {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Self.sub)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("\(event.score ?? 0) pts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.ink)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Self.sub)
    }

    // 画像として描いてクリップボードに入れる。PNG と TIFF の両方を入れて、どの貼り先でも受け取れるようにする
    @MainActor
    static func copy(report: DayReport, streak: Int) -> Bool {
        let renderer = ImageRenderer(content: ReportShareCard(report: report, streak: streak).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
    }
}

// 保存した単語を、幅に収まるだけ並べて折り返す
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
