import GlossCore
import SwiftUI

// 1問ずつ4つから選ぶ。数字キーの 1〜4 でも選べる
struct ChoiceTestPage: View {
    @Environment(QuizStore.self) private var quiz

    var body: some View {
        Group {
            if quiz.quizzableCount == 0 {
                ContentUnavailableView(
                    "No words to test yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Words appear here once their translations are ready in your Book.")
                )
            } else {
                ChoiceQuizView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { quiz.openChoiceQuiz() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Direction", selection: Binding(get: { quiz.state.choiceDirection }, set: { quiz.setChoiceDirection($0) })) {
                    Text("JA → EN").tag(WordDirection.toEnglish)
                    Text("EN → JA").tag(WordDirection.toJapanese)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Button { quiz.startChoiceQuiz() } label: {
                    Label("New Test", systemImage: "arrow.clockwise")
                }
                .help("Start a new test with different words")
                .disabled(quiz.quizzableCount == 0)
            }
        }
    }
}

private struct ChoiceQuizView: View {
    @Environment(QuizStore.self) private var quiz

    var body: some View {
        let direction = quiz.state.choiceDirection
        let state = quiz.state.choices[direction] ?? ChoiceQuizState()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if state.isFinished {
                    ChoiceResult(direction: direction, state: state)
                } else if let word = state.current {
                    // 問題ごとに作り直す。使い回すと、数字キーのショートカットが前の問題の選択肢を選んでしまう
                    ChoiceQuestion(direction: direction, state: state, word: word)
                        .id(word.id)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ChoiceQuestion: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection
    let state: ChoiceQuizState
    let word: WordEntry

    var body: some View {
        let answer = direction.expected(for: word)
        let picked = state.picks[word.id]
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.index + 1) of \(state.questions.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressView(value: Double(state.index), total: Double(state.questions.count))
        }
        Text(direction.prompt(for: word))
            .font(.system(size: 34, weight: .bold))
            .textSelection(.enabled)
        VStack(spacing: 10) {
            ForEach(Array((state.options[word.id] ?? []).enumerated()), id: \.element.text) { offset, option in
                ChoiceButton(number: offset + 1, option: option, answer: answer, picked: picked)
            }
        }
        if let picked {
            HStack {
                if picked == answer {
                    Label("Correct", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Mastery.known.resultTint)
                } else {
                    Label("The answer is \(answer)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Mastery.notYet.resultTint)
                }
                Spacer()
                Button("Next") { quiz.nextChoice() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .help("Next question (↩)")
            }
            .font(.headline)
            .controlSize(.large)
        }
    }
}

// 選んだあとは、正解を緑、外した選択を赤にして、どの選択肢にも意味を出す。色だけに頼らず印も付ける
private struct ChoiceButton: View {
    @Environment(QuizStore.self) private var quiz
    let number: Int
    let option: ChoiceOption
    let answer: String
    let picked: String?

    var body: some View {
        let tint = ChoiceTint.of(option.text, answer: answer, picked: picked)
        Button { quiz.pickChoice(option.text) } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.text)
                        .font(.title3)
                        .multilineTextAlignment(.leading)
                    if picked != nil {
                        Text(option.meaning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let tint {
                    Image(systemName: option.text == answer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10).fill((tint ?? .clear).opacity(0.12)))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.separator), lineWidth: tint == nil ? 1 : 2))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(picked != nil && tint == nil ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [])
    }
}

private struct ChoiceResult: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection
    let state: ChoiceQuizState

    var body: some View {
        let correct = state.correctCount(direction: direction)
        let missed = state.questions.count - correct
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(correct)").font(.system(size: 48, weight: .bold, design: .rounded))
                Text("of \(state.questions.count) correct").font(.title3).foregroundStyle(.secondary)
            }
            Text("Your Book moved up one step for each word you got right, and back to Not Yet for each miss.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        VStack(spacing: 0) {
            ForEach(state.questions) { word in
                ChoiceReviewRow(direction: direction, state: state, word: word)
                Divider()
            }
        }
        HStack(spacing: 12) {
            Spacer()
            if missed > 0 {
                Button("New Test") { quiz.startChoiceQuiz() }
                Button("Retry \(missed) Missed") { quiz.startChoiceQuiz(onlyMissed: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Test only the words you missed (⌘↩)")
            } else {
                Button("New Test") { quiz.startChoiceQuiz() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("New test (⌘↩)")
            }
        }
        .controlSize(.large)
    }
}

enum ChoiceTint {
    static func of(_ option: String, answer: String, picked: String?) -> Color? {
        if picked == nil { return nil }
        if option == answer { return Mastery.known.resultTint }
        if option == picked { return Mastery.notYet.resultTint }
        return nil
    }
}

// 押すと、その問題の4つの選択肢と意味を開いて振り返れる
private struct ChoiceReviewRow: View {
    let direction: WordDirection
    let state: ChoiceQuizState
    let word: WordEntry
    @State private var isOpen = false

    var body: some View {
        let isCorrect = state.isCorrect(word, direction: direction)
        let answer = direction.expected(for: word)
        let picked = state.picks[word.id]
        VStack(alignment: .leading, spacing: 8) {
            Button { isOpen.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isCorrect ? Mastery.known.resultTint : Mastery.notYet.resultTint)
                    Text(direction.prompt(for: word)).font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    if !isCorrect, let picked {
                        Text(picked).strikethrough().foregroundStyle(.secondary)
                    }
                    Text(answer)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Hide the choices" : "Show all four choices and their meanings")
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.options[word.id] ?? [], id: \.text) { option in
                        let tint = ChoiceTint.of(option.text, answer: answer, picked: picked)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: option.text == answer ? "checkmark" : option.text == picked ? "xmark" : "circle")
                                .font(.caption)
                                .foregroundStyle(tint ?? .secondary)
                                .frame(width: 16)
                            Text(option.text).font(.body.weight(.medium))
                            Text(option.meaning).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 30)
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }
}
