import Foundation
import GlossCore
import Observation

struct AskState {
    var isPanelOpen = false
    var focus = ""
    var thread: [ChatMessage] = []
    var draft = ""
    var isAsking = false
    var error: String?
    // 答えから抜き出した、覚えるべき単語やフレーズ。単語帳に入れるのは選んだ範囲ではなくこちら
    var chunks: [StudyChunk] = []

    var hasAnswer: Bool {
        thread.contains { $0.role == .assistant && !$0.text.isEmpty }
    }
}

// 答えは単語帳に保存するので WordsStore を持つ。単語帳から質問を開くときは、画面が両方を呼ぶ
@MainActor
@Observable
final class AskStore {
    // 文や段落ごと選んだときは質問しない。調べたい語句ではなく、コピーなどのための選択とみなす
    static let maxMouseSelectionLength = 60

    private(set) var state = AskState()
    private let settings: SettingsStore
    private let words: WordsStore
    private var task: Task<Void, Never>?
    // 質問の文脈。翻訳画面では原文と訳文、カードから聞くときは保存した用例
    private var source = ""
    private var translation = ""
    // 自動で入れたか、ユーザーが外した・入れた表現。一度扱ったものは、次の答えで足し直さない
    private var handledChunks: Set<String> = []
    // 外した直後に戻せるよう、外した単語を学習記録ごと取っておく
    private var removedEntries: [String: WordEntry] = [:]
    // 英作テストの解説では、抜き出した表現を勝手に入れず、押したものだけ単語帳に入れる
    private var savesChunksAutomatically = true

    init(settings: SettingsStore, words: WordsStore) {
        self.settings = settings
        self.words = words
    }

    var focusWord: WordEntry? {
        words.entry(for: state.focus)
    }

    func isSaved(_ chunk: StudyChunk) -> Bool {
        words.entry(for: chunk.expression) != nil
    }

    func setPanelOpen(_ isOpen: Bool) {
        state.isPanelOpen = isOpen
    }

    func setDraft(_ draft: String) {
        state.draft = draft
    }

    func askAboutMouseSelection(_ text: String, source: String, translation: String, autoSave: Bool = true) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phrase.count <= Self.maxMouseSelectionLength, !phrase.contains(where: \.isNewline), phrase != state.focus
        else { return }
        ask(about: phrase, source: source, translation: translation, autoSave: autoSave)
    }

    // 英作・英文訳テストの採点を、解説として右のパネルに出す。見出しの英文について続けて質問できる
    // 解説は本文に出しているので、パネルは空の会話から始める。解説は AI に渡す文脈にだけ入れる
    func openReview(focus: String, source: String, translation: String, grade: WritingGrade) {
        task?.cancel()
        state.isAsking = false
        state.focus = focus
        state.error = nil
        self.source = source
        self.translation = translation + "\n\n# 採点(\(grade.score) 点)と解説\n" + grade.feedback
        state.thread = []
        state.chunks = []
        handledChunks = []
        removedEntries = [:]
        savesChunksAutomatically = false
        state.isPanelOpen = true
    }

    func ask(about phrase: String, source: String, translation: String, autoSave: Bool = true) {
        guard !phrase.isEmpty else { return }
        task?.cancel()
        savesChunksAutomatically = autoSave
        state.focus = phrase
        state.thread = []
        state.chunks = []
        state.error = nil
        self.source = source
        self.translation = translation
        handledChunks = []
        removedEntries = [:]
        state.isPanelOpen = true
        send(Prompts.quickQuestions[0].question(about: phrase))
    }

    // カードから聞くときは、保存済みの説明を最初の答えとして並べて、続きから質問できるようにする。
    // もう単語帳にあるので、追加の答えで説明を上書きしない
    func open(_ word: WordEntry) {
        task?.cancel()
        state.isAsking = false
        state.focus = word.term
        state.error = nil
        source = word.context
        translation = ""
        state.thread = word.note.isEmpty ? [] : [
            ChatMessage(.user, Prompts.quickQuestions[0].question(about: word.term)),
            ChatMessage(.assistant, word.note),
        ]
        state.chunks = [StudyChunk(expression: word.term, meaning: word.japanese ?? "")]
        handledChunks = [word.term.lowercased()]
        removedEntries = [:]
        savesChunksAutomatically = true
        state.isPanelOpen = true
        if state.thread.isEmpty { send(Prompts.quickQuestions[0].question(about: word.term)) }
    }

    // 単語テストの結果から聞くときは、採点のコメントを最初の答えとして並べる。
    // 問題・自分の答え・正解を文脈に入れて、「なぜ違うの?」にそのまま答えられるようにする
    func open(_ word: WordEntry, prompt: String, expected: String, answer: String, grade: WordGrade) {
        task?.cancel()
        state.isAsking = false
        state.focus = word.term
        state.error = nil
        let written = answer.isEmpty ? "(空欄)" : answer
        source = word.context
        translation = "単語テスト: 問題「\(prompt)」に対して、学習者は「\(written)」と書いた。"
            + "想定の答えは「\(expected)」で、判定は「\(grade.verdict.label)」。"
        let summary = [grade.comment, word.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
        state.thread = [
            ChatMessage(.user, "「\(prompt)」を「\(written)」と書いたら \(grade.verdict.label) でした。正解は「\(expected)」です"),
            ChatMessage(.assistant, summary.isEmpty ? "正解は「\(expected)」です。" : summary),
        ]
        state.chunks = [StudyChunk(expression: word.term, meaning: word.japanese ?? "")]
        handledChunks = [word.term.lowercased()]
        removedEntries = [:]
        savesChunksAutomatically = true
        state.isPanelOpen = true
    }

    // パネルは閉じずに中身だけ消す。閉じると詳細の幅が変わって、隣の画面がずれるため
    func clear() {
        task?.cancel()
        state.isAsking = false
        state.focus = ""
        state.thread = []
        state.chunks = []
        state.error = nil
        state.draft = ""
    }

    func sendDraft() {
        let question = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !state.focus.isEmpty else { return }
        state.draft = ""
        send(question)
    }

    func send(_ question: String) {
        task?.cancel()
        state.error = nil
        let focus = state.focus
        let context = ChatMessage(.system, Prompts.tutor(source: source, translation: translation, focus: focus))
        state.thread.append(ChatMessage(.user, question))
        let request = [context] + state.thread
        state.thread.append(ChatMessage(.assistant, ""))
        let answerIndex = state.thread.count - 1
        state.isAsking = true
        let client = settings.makeClient()

        task = Task {
            var raw = ""
            do {
                for try await piece in client.stream(request) {
                    guard !Task.isCancelled, state.thread.indices.contains(answerIndex) else { return }
                    raw += piece
                    state.thread[answerIndex].text = Prompts.splitChunks(raw).text
                }
                guard !Task.isCancelled, focus == state.focus else { return }
                // 答えが最後まで出たら、抜き出した表現を全部単語帳に入れる
                let answer = Prompts.splitChunks(raw)
                for chunk in answer.chunks {
                    if !state.chunks.contains(where: { $0.id == chunk.id }) { state.chunks.append(chunk) }
                    guard savesChunksAutomatically, !handledChunks.contains(chunk.id) else { continue }
                    handledChunks.insert(chunk.id)
                    save(chunk, note: answer.text)
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { state.error = error.localizedDescription }
            }
            // 次の質問が始まっているときに、その isAsking を落とさない
            guard !Task.isCancelled else { return }
            state.isAsking = false
        }
    }

    // パネルのボタンで、表現を単語帳から外す・入れるを切り替える。入れるときは出きった最後の答えを説明に使う
    func toggleSaved(_ chunk: StudyChunk) {
        handledChunks.insert(chunk.id)
        if isSaved(chunk) {
            removedEntries[chunk.id] = words.remove(term: chunk.expression)
            return
        }
        guard let note = state.thread.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text else { return }
        save(chunk, note: note)
    }

    private func save(_ chunk: StudyChunk, note: String) {
        words.saveAnswer(term: chunk.expression, note: note, context: usageSentence(for: chunk), restoring: removedEntries[chunk.id])
        removedEntries[chunk.id] = nil
    }

    // 用例は、その表現を含む原文の1文。表現が原文にそのまま無いときは、選んだ範囲を含む1文にする
    private func usageSentence(for chunk: StudyChunk) -> String {
        Sentence.containing(chunk.expression, in: source)
            ?? Sentence.containing(state.focus, in: source)
            ?? Sentence.containing(state.focus, in: translation)
            ?? ""
    }
}
