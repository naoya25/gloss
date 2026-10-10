import GlossCore
import SwiftUI

struct WordCard: View {
    @Environment(WordsStore.self) private var words
    @Environment(AskStore.self) private var ask
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let word: WordEntry
    let face: CardFace
    let isOpen: Bool

    private var backFace: CardFace { face == .english ? .japanese : .english }

    var body: some View {
        // カードは動かさず、文字だけを入れ替える。表の文字は一文字ずつぼやけながら上へ抜け、
        // 裏の文字は下から浮かび上がる。横長のカードを回すと動く距離が長くなるため。
        // 表と裏を同じ場所に重ねないと入れ替えられないので、ここは ZStack を使う
        CardSurface(isOpen: isOpen) {
            ZStack(alignment: .leading) {
                CardText(text: word.hasCardPair ? word.text(for: face) : word.term, isShown: !isOpen, direction: -1)
                CardText(text: word.hasCardPair ? word.text(for: backFace) : word.term, isShown: isOpen, direction: 1)
            }
            Spacer(minLength: 12)
            ZStack(alignment: .trailing) {
                ReviewInfo(word: word)
                    .opacity(isOpen ? 0 : 1)
                    .blur(radius: isOpen && !reduceMotion ? 4 : 0)
                    .allowsHitTesting(!isOpen)
                MasteryPicker(word: word)
                    .opacity(isOpen ? 1 : 0)
                    .blur(radius: !isOpen && !reduceMotion ? 4 : 0)
                    .allowsHitTesting(isOpen)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: flip)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.7), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Flip back" : "Flip to see the translation")
        .contextMenu {
            Button("Regenerate Translation and Example") { words.regenerate(word.id) }
            Button("Delete from Book", role: .destructive) { words.delete(word.id) }
        }
    }

    // めくったカードの説明を右のパネルに出して、そのまま続きを質問できるようにする
    private func flip() {
        if words.flip(word.id) {
            ask.open(word)
        } else {
            ask.clear()
        }
    }
}

private struct CardText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let isShown: Bool
    let direction: Double

    var body: some View {
        if #available(macOS 15, *) {
            Text(text)
                .font(.title3.weight(.semibold))
                .textRenderer(GlyphRise(progress: isShown ? 1 : 0, direction: direction, moves: !reduceMotion))
                .lineLimit(1)
                .accessibilityHidden(!isShown)
        } else {
            Text(text)
                .font(.title3.weight(.semibold))
                .opacity(isShown ? 1 : 0)
                .lineLimit(1)
                .accessibilityHidden(!isShown)
        }
    }
}

// 表の右側は、覚えた度合いの印・めくった回数・最後にめくった日だけ。言葉の説明はマウスを乗せたときに出す
private struct ReviewInfo: View {
    let word: WordEntry

    var body: some View {
        HStack(spacing: 10) {
            CardStatus(word: word)
            Image(systemName: word.masteryLevel.symbol)
                .foregroundStyle(word.masteryLevel.tint)
            Text(summary)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .help(helpText)
    }

    private var summary: String {
        guard let date = word.lastReviewed else { return "0 flips" }
        return "\(word.flipCount) \(word.flipCount == 1 ? "flip" : "flips") · \(Self.daysAgo(date))"
    }

    private var helpText: String {
        let last = word.lastReviewed.map { $0.formatted(.dateTime.year().month().day()) } ?? "never"
        return "\(word.masteryLevel.label) · flipped \(word.flipCount) times · last flipped \(last)"
    }

    static func daysAgo(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days)d ago"
        }
    }
}

// 1行に収めるため、作成中と失敗は文ではなく印で出し、理由はマウスを乗せたときに出す
private struct CardStatus: View {
    @Environment(SettingsStore.self) private var settings
    let word: WordEntry

    var body: some View {
        if word.isCardComplete {
            EmptyView()
        } else if let error = word.cardError {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .help("Couldn't create the translation and example (\(error)). Right-click to regenerate.")
        } else if word.engine != settings.state.engine {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .help("Right-click and choose Regenerate to create them with the current engine.")
        } else {
            ProgressView()
                .controlSize(.mini)
                .help("Creating the translation and example")
        }
    }
}

private struct MasteryPicker: View {
    @Environment(WordsStore.self) private var words
    let word: WordEntry

    var body: some View {
        Picker("Mastery", selection: Binding(get: { word.masteryLevel }, set: { words.setMastery($0, for: word.id) })) {
            ForEach(Mastery.allCases) { level in
                Label(level.label, systemImage: level.symbol)
                    .labelStyle(.iconOnly)
                    .tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Mastery: ✕ Not Yet / ? Unsure / ✓ Known")
    }
}

extension Mastery {
    var symbol: String {
        switch self {
        case .notYet: "xmark"
        case .unsure: "questionmark"
        case .known: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .notYet: .secondary
        case .unsure: .orange
        case .known: .green
        }
    }
}
