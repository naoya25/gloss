import GlossCore
import SwiftUI

struct WordTestPage: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection

    var body: some View {
        Group {
            if quiz.quizzableCount == 0 {
                ContentUnavailableView(
                    "No words to test yet",
                    systemImage: "character.textbox",
                    description: Text("Words appear here once their translations are ready in your Book.")
                )
            } else {
                WordQuizView(direction: direction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { quiz.openWordQuiz(direction) }
        .toolbar {
            ToolbarItem {
                Button { quiz.startWordQuiz(direction) } label: {
                    Label("New Test", systemImage: "arrow.clockwise")
                }
                .help("Start a new test with different words")
                .disabled(quiz.quizzableCount == 0)
            }
        }
    }
}

// 書いている間は右のパネルを閉じて、お題と自分の答えだけにする。採点が出たら、パネルに解説を出す
struct ExercisePage: View {
    @Environment(QuizStore.self) private var quiz
    @Environment(AskStore.self) private var ask
    let kind: ExerciseKind

    var body: some View {
        WritingQuizView(kind: kind)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                quiz.openExercise(kind)
                showReview()
            }
            .onChange(of: quiz.state[kind].grade) { showReview() }
            .toolbar {
                ToolbarItem {
                    Button { quiz.nextExercise(kind) } label: {
                        Label("Skip", systemImage: "forward")
                    }
                    .help("Skip to a different task")
                    .disabled(quiz.state[kind].isLoading)
                }
            }
    }

    private func showReview() {
        let state = quiz.state[kind]
        if let grade = state.grade, let task = state.task {
            ask.openReview(kind, task: task, answer: state.answer, grade: grade)
        } else {
            ask.clear()
            ask.setPanelOpen(false)
        }
    }
}

// 10問を1枚に並べて、全部書いてからまとめて採点する。日本語訳が同じ単語どうしを見比べて書き分けられるように
private struct WordQuizView: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection

    var body: some View {
        let state = quiz.state[direction]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if state.isGraded {
                    WordQuizScore(direction: direction)
                } else {
                    WordQuizHeader(direction: direction)
                }
                VStack(spacing: 8) {
                    ForEach(Array(state.questions.enumerated()), id: \.element.id) { offset, word in
                        WordQuizRow(direction: direction, number: offset + 1, word: word)
                    }
                }
                WordQuizActions(direction: direction)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WordQuizHeader: View {
    let direction: WordDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(direction == .toEnglish ? "Word Test" : "Meaning Test").font(.largeTitle.weight(.bold))
            Text(direction == .toEnglish
                ? "Write the English for each one, then check them all at once."
                : "Write the Japanese meaning for each one, then check them all at once.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// 採点の瞬間がこのテストの山場なので、点数を輪で大きく見せて、内訳と Book の変化を並べる
private struct WordQuizScore: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let state = quiz.state[direction]
        let total = max(state.questions.count, 1)
        let counts = Dictionary(grouping: state.grades.values, by: \.verdict).mapValues(\.count)
        let known = counts[.known] ?? 0
        let unsure = counts[.unsure] ?? 0
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: shown ? Double(known + unsure) / Double(total) : 0)
                    .stroke(Mastery.unsure.resultTint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: shown ? Double(known) / Double(total) : 0)
                    .stroke(Mastery.known.resultTint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(known)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("of \(state.questions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 12) {
                Text(Self.headline(known: known, total: state.questions.count))
                    .font(.title.weight(.bold))
                HStack(spacing: 8) {
                    ForEach(Mastery.allCases.reversed()) { level in
                        VerdictChip(verdict: level, count: counts[level] ?? 0)
                    }
                }
                Text("Your Book was updated. Click a word to ask about it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 1.1).delay(0.15)) { shown = true }
        }
        .onChange(of: state.questions.map(\.id)) { shown = false }
    }

    static func headline(known: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        switch Double(known) / Double(total) {
        case 1: return "Perfect!"
        case 0.8...: return "Great job!"
        case 0.5...: return "Nice progress"
        case 0.01...: return "Keep going"
        default: return "Every miss is a word you'll know next time"
        }
    }
}

private struct VerdictChip: View {
    let verdict: Mastery
    let count: Int

    var body: some View {
        Label("\(count) \(verdict.label)", systemImage: verdict.symbol)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(verdict.resultTint.opacity(count == 0 ? 0.06 : 0.16)))
            .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(verdict.resultTint))
    }
}

// 採点のあとは、行の左端の色帯と印で正誤を見分ける。色だけに頼らず、印の形と言葉も変える
private struct WordQuizRow: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection
    @Environment(AskStore.self) private var ask
    let number: Int
    let word: WordEntry

    var body: some View {
        let grade = quiz.state[direction].grades[word.id]
        let tint = grade?.verdict.resultTint ?? .clear
        let isAsked = grade != nil && ask.state.focus == word.term
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let grade {
                GradeMark(verdict: grade.verdict) { quiz.overrideGrade($0, for: word.id, in: direction) }
                    .frame(width: 24)
            } else {
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
            }
            Text(direction.prompt(for: word))
                .font(.body.weight(.semibold))
                .frame(width: 170, alignment: .leading)
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 4) {
                if let grade {
                    GradedAnswer(direction: direction, word: word, answer: quiz.state[direction].answer(for: word.id), grade: grade)
                } else {
                    AnswerField(
                        text: Binding(get: { quiz.state[direction].answer(for: word.id) }, set: { quiz.setWordAnswer($0, for: word.id, in: direction) }),
                        placeholder: direction == .toEnglish ? "English" : "日本語",
                        isEnabled: !quiz.state[direction].isGrading,
                        focusesOnAppear: number == 1
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.07)))
        }
        .overlay(alignment: .leading) {
            if grade != nil {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(tint)
                    .frame(width: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isAsked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: isAsked ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // 採点のあとは、行を押すと右のパネルでこの単語について質問できる
        .onTapGesture {
            guard let grade else { return }
            ask.open(word, prompt: direction.prompt(for: word), expected: direction.expected(for: word), answer: quiz.state[direction].answer(for: word.id), grade: grade)
        }
        .help(grade == nil ? "" : "Click to ask about this word")
    }
}

private struct GradedAnswer: View {
    let direction: WordDirection
    let word: WordEntry
    let answer: String
    let grade: WordGrade

    var body: some View {
        let expected = direction.expected(for: word)
        let exact = WordQuiz.isCorrect(answer, for: word, direction: direction)
        switch grade.verdict {
        case .known:
            Text(answer).font(.body.weight(.medium))
            // 別の言い方で正解したときだけ、Book の答えも添える
            if !exact {
                Text("Book: \(expected)").font(.callout).foregroundStyle(.secondary)
            }
        case .unsure, .notYet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(answer.isEmpty ? "(blank)" : answer)
                    .strikethrough(!answer.isEmpty)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(expected)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Mastery.known.resultTint)
            }
        }
        if !grade.comment.isEmpty {
            Text(grade.comment).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// 印を押すと、この問題の判定と Book の度合いを変えられる
private struct GradeMark: View {
    let verdict: Mastery
    let change: (Mastery) -> Void

    var body: some View {
        Menu {
            ForEach(Mastery.allCases) { level in
                Button { change(level) } label: { Label(level.label, systemImage: level.symbol) }
            }
        } label: {
            Image(systemName: verdict.symbol + ".circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, verdict.resultTint)
        }
        // borderlessButton にすると印の色が灰色に塗られるので、ボタンの見た目を外して色を残す
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(verdict.label). Click to change it")
        .accessibilityLabel(verdict.label)
    }
}

private struct WordQuizActions: View {
    @Environment(QuizStore.self) private var quiz
    let direction: WordDirection

    var body: some View {
        let state = quiz.state[direction]
        let missed = state.questions.filter { state.grades[$0.id]?.verdict != .known }.count
        HStack(spacing: 12) {
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isGrading {
                ProgressView().controlSize(.small)
            }
            if state.isGraded {
                if missed > 0 {
                    Button("New Test") { quiz.startWordQuiz(direction) }
                    Button("Retry \(missed) Missed") { quiz.retryMissed(direction) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Test only the words you missed (⌘↩)")
                } else {
                    Button("New Test") { quiz.startWordQuiz(direction) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("New test (⌘↩)")
                }
            } else {
                Button("Check All") { quiz.gradeWordQuiz(direction) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(state.isGrading)
                    .help("Check all answers (⌘↩)")
            }
        }
        .controlSize(.large)
    }
}

extension Mastery {
    // テストの結果では、覚えてないも赤で目立たせる。Book のカードでは灰色のまま
    var resultTint: Color {
        switch self {
        case .notYet: .red
        case .unsure: .orange
        case .known: .green
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct WritingQuizView: View {
    @Environment(QuizStore.self) private var quiz
    let kind: ExerciseKind

    var body: some View {
        let state = quiz.state[kind]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !state.scores.isEmpty {
                    Text("\(state.scores.count) done · average \(state.scores.reduce(0, +) / state.scores.count) pts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let task = state.task {
                    WritingTaskCard(kind: kind, task: task, isGraded: state.grade != nil)
                    WritingAnswerEditor(kind: kind)
                    if let grade = state.grade {
                        WritingGradeView(kind: kind, grade: grade)
                    }
                } else if state.isLoading {
                    ProgressView("Creating a task…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
                if let error = state.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("Try Again") { state.task == nil ? quiz.nextExercise(kind) : quiz.submitExercise(kind) }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

// 英文訳テストでは、採点のあとに英文の語句を選ぶと、右のパネルで質問できる。答えている間はヒントにならないよう選んでも何もしない
private struct WritingTaskCard: View {
    @Environment(AskStore.self) private var ask
    let kind: ExerciseKind
    let task: WritingTask
    let isGraded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !task.scene.isEmpty {
                Text(task.scene)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            if kind == .reading && isGraded {
                GlossTextView(
                    text: .constant(task.task),
                    isEditable: false,
                    onMouseSelect: { ask.askAboutMouseSelection($0, source: task.task, translation: "", autoSave: false) }
                )
                .frame(height: WritingGradeView.height(for: task.task, fontSize: 17))
            } else {
                Text(task.task)
                    .font(kind == .reading ? .system(size: 19, weight: .medium) : .title3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WritingAnswerEditor: View {
    @Environment(QuizStore.self) private var quiz
    let kind: ExerciseKind
    @FocusState private var isFocused: Bool

    var body: some View {
        let state = quiz.state[kind]
        VStack(alignment: .trailing, spacing: 10) {
            TextEditor(text: Binding(get: { state.answer }, set: { quiz.setExerciseAnswer($0, for: kind) }))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .overlay(alignment: .topLeading) {
                    if state.answer.isEmpty {
                        Text(kind == .writing ? "Write in English" : "日本語に訳してください")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .focused($isFocused)
                .disabled(state.grade != nil)
            HStack(spacing: 12) {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                }
                if state.grade == nil {
                    Button("Score") { quiz.submitExercise(kind) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isLoading)
                        .help("Score (⌘↩)")
                } else {
                    Button("Next Task") { quiz.nextExercise(kind) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Next task (⌘↩)")
                }
            }
            .controlSize(.large)
        }
        .onAppear { isFocused = true }
    }
}

// 解説と覚える表現は右のパネルに出す。ここには点数と直した英文だけを置き、英文の語句を選ぶとパネルで質問できる
private struct WritingGradeView: View {
    @Environment(QuizStore.self) private var quiz
    let kind: ExerciseKind
    @Environment(AskStore.self) private var ask
    let grade: WritingGrade

    private var tint: Color {
        switch grade.score {
        case 80...: .green
        case 50..<80: .orange
        default: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(grade.score)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("pts").foregroundStyle(.secondary)
                Spacer()
                Button("Ask About This", action: showReview)
                    .disabled(ask.state.focus == reviewFocus && ask.state.isPanelOpen && ask.state.thread.isEmpty)
                    .help("Ask about this review in the side panel")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .writing ? "Natural English" : "Model Translation").font(.caption).foregroundStyle(.secondary)
                if kind == .writing {
                    GlossTextView(
                        text: .constant(grade.corrected),
                        isEditable: false,
                        onMouseSelect: { ask.askAboutMouseSelection($0, source: source, translation: grade.corrected, autoSave: false) }
                    )
                    .frame(height: Self.height(for: grade.corrected))
                } else {
                    Text(grade.corrected)
                        .font(.system(size: 16, weight: .medium))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
                Text(kind == .writing
                    ? "Select a word or phrase to ask about it in the side panel."
                    : "Select a word or phrase in the English above to ask about it in the side panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, kind == .writing ? 0 : 16)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
            Text(LocalizedStringKey(grade.feedback))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !grade.chunks.isEmpty {
                ReviewChunks(kind: kind, chunks: grade.chunks)
            }
        }
        .transition(.opacity)
    }

    private var source: String {
        let task = quiz.state[kind].task
        return "英作テストのお題(\(task?.scene ?? "")): \(task?.task ?? "")\n学習者の英文: \(quiz.state[kind].answer)"
    }

    private var reviewFocus: String {
        kind == .writing ? grade.corrected : (quiz.state[kind].task?.task ?? "")
    }

    private func showReview() {
        guard let task = quiz.state[kind].task else { return }
        ask.openReview(kind, task: task, answer: quiz.state[kind].answer, grade: grade)
    }

    // 読み取り専用の欄は中身の高さに合わせないので、文字数からおおよその行数を出して高さを決める
    static func height(for text: String, fontSize: CGFloat = 15) -> CGFloat {
        let perLine = 62 * 15 / fontSize
        let lines = max(1, Int((Double(text.count) / perLine).rounded(.up)))
        return CGFloat(lines) * (fontSize + 9) + 32
    }
}

// 採点から抜き出した覚える表現。押したものだけ Book に入れる
private struct ReviewChunks: View {
    @Environment(QuizStore.self) private var quiz
    @Environment(WordsStore.self) private var words
    let kind: ExerciseKind
    let chunks: [StudyChunk]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expressions to learn", systemImage: "bookmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(chunks) { chunk in
                let isSaved = words.entry(for: chunk.expression) != nil
                Button {
                    quiz.toggleChunk(chunk, in: kind)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(chunk.expression).fontWeight(.semibold)
                        if !chunk.meaning.isEmpty {
                            Text(chunk.meaning).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .help(isSaved ? "In your Book. Click to remove it" : "Click to add it to your Book")
            }
        }
    }
}

extension AskStore {
    // 英作テストは直した英文を、英文訳テストは元の英文を見出しにする。覚える表現はどちらも英文から出る
    func openReview(_ kind: ExerciseKind, task: WritingTask, answer: String, grade: WritingGrade) {
        switch kind {
        case .writing:
            openReview(
                focus: grade.corrected,
                source: "英作テストのお題(\(task.scene)): \(task.task)\n学習者の英文: \(answer)",
                translation: grade.corrected,
                grade: grade
            )
        case .reading:
            openReview(
                focus: task.task,
                source: task.task,
                translation: "模範訳: \(grade.corrected)\n学習者の訳: \(answer)",
                grade: grade
            )
        }
    }
}
