import Foundation
import GlossCore
import Observation

struct WordQuizState {
    var questions: [WordEntry] = []
    var answers: [UUID: String] = [:]
    // 採点前は空。採点が終わると全問ぶん入る
    var grades: [UUID: WordGrade] = [:]
    var isGrading = false
    var error: String?

    var isGraded: Bool { !questions.isEmpty && grades.count == questions.count }
    var knownCount: Int { grades.values.filter { $0.verdict == .known }.count }

    func answer(for id: UUID) -> String { answers[id] ?? "" }
}

struct ExerciseState {
    var task: WritingTask?
    var answer = ""
    var grade: WritingGrade?
    var isLoading = false
    var error: String?
    var scores: [Int] = []
}

// テストは種類ごとに別々に持つ。サイドバーで行き来しても、途中の答えが消えないように
struct QuizState {
    var words = WordQuizState()
    var meanings = WordQuizState()
    var writing = ExerciseState()
    var reading = ExerciseState()

    subscript(direction: WordDirection) -> WordQuizState {
        get { direction == .toEnglish ? words : meanings }
        set { if direction == .toEnglish { words = newValue } else { meanings = newValue } }
    }

    subscript(kind: ExerciseKind) -> ExerciseState {
        get { kind == .writing ? writing : reading }
        set { if kind == .writing { writing = newValue } else { reading = newValue } }
    }
}

@MainActor
@Observable
final class QuizStore {
    private(set) var state = QuizState()
    private let settings: SettingsStore
    private let words: WordsStore
    private let activity: ActivityStore
    private var wordTasks: [WordDirection: Task<Void, Never>] = [:]
    private var exerciseTasks: [ExerciseKind: Task<Void, Never>] = [:]
    // 外した直後に戻せるよう、外した単語を学習記録ごと取っておく
    private var removedChunks: [String: WordEntry] = [:]

    init(settings: SettingsStore, words: WordsStore, activity: ActivityStore) {
        self.settings = settings
        self.words = words
        self.activity = activity
    }

    var quizzableCount: Int { words.state.words.filter(\.hasCardPair).count }

    func openWordQuiz(_ direction: WordDirection) {
        if state[direction].questions.isEmpty { startWordQuiz(direction) }
    }

    func startWordQuiz(_ direction: WordDirection) {
        wordTasks[direction]?.cancel()
        state[direction] = WordQuizState(questions: WordQuiz.pick(from: words.state.words))
    }

    // 間違えた単語と惜しかった単語だけで、もう一度テストする
    func retryMissed(_ direction: WordDirection) {
        let quiz = state[direction]
        let missed = quiz.questions.filter { quiz.grades[$0.id]?.verdict != .known }
        guard !missed.isEmpty else { return }
        wordTasks[direction]?.cancel()
        state[direction] = WordQuizState(questions: missed.compactMap { word in self.words.state.words.first { $0.id == word.id } })
    }

    func setWordAnswer(_ answer: String, for id: UUID, in direction: WordDirection) {
        state[direction].answers[id] = answer
    }

    // 全問まとめて採点する。答えと同じものはその場で正解にして、残りだけ AI に見てもらう
    func gradeWordQuiz(_ direction: WordDirection) {
        let quiz = state[direction]
        guard !quiz.isGraded, !quiz.isGrading else { return }
        var grades: [UUID: WordGrade] = [:]
        var items: [WordTestItem] = []
        for (offset, word) in quiz.questions.enumerated() {
            let answer = quiz.answer(for: word.id).trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty {
                grades[word.id] = WordGrade(verdict: .notYet, comment: "")
            } else if WordQuiz.isCorrect(answer, for: word, direction: direction) {
                grades[word.id] = WordGrade(verdict: .known)
            } else {
                items.append(WordTestItem(number: offset + 1, prompt: direction.prompt(for: word), expected: direction.expected(for: word), answer: answer))
            }
        }
        guard !items.isEmpty else {
            finishWordQuiz(direction, with: grades)
            return
        }
        state[direction].isGrading = true
        state[direction].error = nil
        let client = settings.makeClient()
        let questions = quiz.questions
        wordTasks[direction] = Task {
            do {
                let raw = try await collect(client, [ChatMessage(.user, Prompts.wordTestReview(items, direction: direction))])
                guard !Task.isCancelled else { return }
                let reviewed = Prompts.parseWordTestReview(raw)
                guard items.allSatisfy({ reviewed[$0.number] != nil }) else {
                    state[direction].isGrading = false
                    state[direction].error = "Couldn't read the grades. Please try again."
                    return
                }
                for item in items {
                    grades[questions[item.number - 1].id] = reviewed[item.number]
                }
                state[direction].isGrading = false
                finishWordQuiz(direction, with: grades)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                state[direction].isGrading = false
                state[direction].error = error.localizedDescription
            }
        }
    }

    // 採点に納得できない問題は、印を押して変えられる。Book の度合いも一緒に変わる
    func overrideGrade(_ verdict: Mastery, for id: UUID, in direction: WordDirection) {
        guard var grade = state[direction].grades[id] else { return }
        grade.verdict = verdict
        state[direction].grades[id] = grade
        words.setMastery(verdict, for: id)
    }

    private func finishWordQuiz(_ direction: WordDirection, with grades: [UUID: WordGrade]) {
        state[direction].grades = grades
        for (id, grade) in grades {
            words.recordQuizAnswer(id, mastery: grade.verdict)
        }
        let kind: ActivityKind = direction == .toEnglish ? .wordQuiz : .meaningQuiz
        let quiz = state[direction]
        let answers = quiz.questions.compactMap { word in
            grades[word.id].map { WordAnswer(wordID: word.id, prompt: direction.prompt(for: word), answer: quiz.answer(for: word.id), verdict: $0.verdict) }
        }
        activity.record(ActivityEvent(kind: kind, title: kind.label, score: quiz.knownCount, total: quiz.questions.count, answers: answers))
    }

    func openExercise(_ kind: ExerciseKind) {
        let exercise = state[kind]
        guard exercise.task == nil, !exercise.isLoading, exercise.error == nil else { return }
        nextExercise(kind)
    }

    // 採点から抜き出した表現を、押したときだけ Book に入れる・外す。用例は直した英文か、元の英文
    func toggleChunk(_ chunk: StudyChunk, in kind: ExerciseKind) {
        if words.entry(for: chunk.expression) != nil {
            removedChunks[chunk.id] = words.remove(term: chunk.expression)
            return
        }
        let exercise = state[kind]
        let context = kind == .writing ? exercise.grade?.corrected ?? "" : exercise.task?.task ?? ""
        words.saveAnswer(term: chunk.expression, note: chunk.meaning, context: Sentence.containing(chunk.expression, in: context) ?? context, restoring: removedChunks[chunk.id])
        removedChunks[chunk.id] = nil
    }

    func setExerciseAnswer(_ answer: String, for kind: ExerciseKind) {
        state[kind].answer = answer
    }

    func nextExercise(_ kind: ExerciseKind) {
        exerciseTasks[kind]?.cancel()
        state[kind].task = nil
        state[kind].answer = ""
        state[kind].grade = nil
        state[kind].error = nil
        state[kind].isLoading = true
        // 単語帳でまだ覚えていない表現を、お題に混ぜて使わせる
        let expressions = words.state.words
            .filter { $0.masteryLevel != .known }
            .shuffled()
            .prefix(3)
            .map(\.term)
        let prompt = kind == .writing ? Prompts.writingTask(using: expressions) : Prompts.readingTask(using: expressions)
        let client = settings.makeClient()
        exerciseTasks[kind] = Task {
            do {
                let raw = try await collect(client, [ChatMessage(.user, prompt)])
                guard !Task.isCancelled else { return }
                if let parsed = Prompts.parseWritingTask(raw) {
                    state[kind].task = parsed
                } else {
                    state[kind].error = "Couldn't create a task. Please try again."
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state[kind].error = error.localizedDescription
            }
            state[kind].isLoading = false
        }
    }

    func submitExercise(_ kind: ExerciseKind) {
        let exercise = state[kind]
        let answer = exercise.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = exercise.task, !answer.isEmpty, exercise.grade == nil else { return }
        exerciseTasks[kind]?.cancel()
        state[kind].error = nil
        state[kind].isLoading = true
        let prompt = kind == .writing
            ? Prompts.writingReview(task: current, answer: answer)
            : Prompts.readingReview(task: current, answer: answer)
        let client = settings.makeClient()
        exerciseTasks[kind] = Task {
            do {
                let raw = try await collect(client, [ChatMessage(.user, prompt)])
                guard !Task.isCancelled else { return }
                if let grade = Prompts.parseWritingGrade(raw) {
                    state[kind].grade = grade
                    state[kind].scores.append(grade.score)
                    activity.record(ActivityEvent(kind: kind == .writing ? .writing : .reading, title: current.task, score: grade.score, detail: grade.corrected, answer: answer))
                } else {
                    state[kind].error = "Couldn't read the score. Please submit again."
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state[kind].error = error.localizedDescription
            }
            state[kind].isLoading = false
        }
    }

    private func collect(_ client: ChatClient, _ messages: [ChatMessage]) async throws -> String {
        var raw = ""
        for try await piece in client.stream(messages) { raw += piece }
        return raw
    }
}
