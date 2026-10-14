import AppKit
import Foundation
import GlossCore
import Observation

struct TranslateState {
    var sourceText = ""
    var sourceImage: Data?
    var translation = ""
    var isTranslating = false
    var error: String?
    var selection = ""
    // 今の訳が、訳し直さずに履歴から出したものか
    var isFromCache = false
    // 訳が出たあとに抜き出して Book に入れた表現
    var extracted: [StudyChunk] = []
    var isExtracting = false
    // 英文の訳。語句ごとに英語と日本語の両方を持ち、level の段階で読む
    var graded: GradedTranslation?
    var level: EnglishLevel = .thirty
    // 読み終えて記録したか。次の英文を貼ったとき・Gloss を閉じるときに1回だけ記録する
    var isRead = false
    // 英語のまま残した表現のうち、質問して意味を確かめたもの。点にしない
    var askedTerms: Set<String> = []
    // 読みながら押して日本語にした語句(小文字の英語)
    var revealed: Set<String> = []

    var mixed: MixedTranslation? { graded?.rendered(level, revealed: revealed) }
    var pendingPoints: Int { level == .japanese ? 0 : mixed?.readingPoints(excluding: askedTerms) ?? 0 }
    // ここまでで英語のまま読めた割合と、それで決まる次の英文の段階
    var ability: Int? { graded.map { $0.readAbility(level, revealed: revealed) } }
    var nextLevel: EnglishLevel? { ability.map(EnglishLevel.above) }

    var canTranslate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceImage != nil
    }
}

@MainActor
@Observable
final class TranslateStore {
    private(set) var state = TranslateState()
    private let settings: SettingsStore
    private let history: HistoryStore
    private let activity: ActivityStore
    private let words: WordsStore
    private var task: Task<Void, Never>?
    private var extractTask: Task<Void, Never>?
    // 外した直後に戻せるよう、外した単語を学習記録ごと取っておく
    private var removedEntries: [String: WordEntry] = [:]

    init(settings: SettingsStore, history: HistoryStore, activity: ActivityStore, words: WordsStore) {
        self.settings = settings
        self.history = history
        self.activity = activity
        self.words = words
        // 読んだまま Gloss を閉じても、読んだ分を記録する
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordReading() }
        }
    }

    func setSourceText(_ text: String) {
        state.sourceText = text
    }

    func select(_ text: String) {
        state.selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setImage(_ data: Data) {
        state.sourceImage = data
        translate()
    }

    func removeImage() {
        state.sourceImage = nil
    }

    func didPasteText() {
        translate()
    }

    func reset() {
        recordReading()
        task?.cancel()
        extractTask?.cancel()
        state = TranslateState()
    }

    // 履歴の一覧で選んだ翻訳を開く
    func open(_ item: HistoryItem, image: Data?) {
        recordReading()
        task?.cancel()
        extractTask?.cancel()
        state = TranslateState(sourceText: item.source, sourceImage: image, translation: item.translation)
    }

    // 質問した範囲に入っている、英語のまま残した表現は点から外す
    func noteAsked(_ text: String) {
        guard let mixed = state.mixed, !state.isRead else { return }
        let asked = text.lowercased()
        for term in mixed.keptTerms where asked.contains(term.lowercased()) || term.lowercased().contains(asked) {
            state.askedTerms.insert(term.lowercased())
        }
    }

    // 段階を変えると、その場で訳を作り直す(AI は呼ばない)
    func setLevel(_ level: EnglishLevel) {
        state.level = level
        settings.setEnglishLevel(level)
    }

    // 押した位置の英語の語句を日本語にする。日本語にした語句をもう一度押すと英語に戻す。
    // 記録するときに日本語のままの語句を、読めなかった語句として数える
    func reveal(at location: Int) {
        guard !state.isRead, let phrase = state.mixed?.clickable(at: location) else { return }
        let key = phrase.english.lowercased()
        if state.revealed.remove(key) == nil { state.revealed.insert(key) }
    }

    // 読み終えた分を記録する。次の英文を貼ったとき・履歴を開いたとき・Gloss を閉じるときに呼ぶ。
    // ほかの画面に移ったときは呼ばない。記録したあとは押せなくなるので、戻ってきて続きを読めなくなる。
    // 英語のまま読めた割合の1段上を次の英文の段階にし、押した語句は Book で ? にする
    func recordReading() {
        guard let graded = state.graded, !graded.phrases.isEmpty, let mixed = state.mixed, let ability = state.ability,
              !state.isRead, !state.isTranslating
        else { return }
        state.isRead = true
        activity.record(ActivityEvent(
            kind: .glossRead,
            title: history.state.items.first?.title ?? "",
            score: state.level == .japanese ? 0 : mixed.englishCharacters,
            total: mixed.totalCharacters,
            detail: "\(state.level.label) · " + mixed.keptTerms.joined(separator: ", "),
            points: state.pendingPoints
        ))
        settings.setEnglishLevel(EnglishLevel.above(ability))
        for phrase in graded.phrases where state.revealed.contains(phrase.english.lowercased()) {
            markUnsure(term: phrase.english, meaning: phrase.japanese)
        }
    }

    // 読めなかった語句を Book で ? にする。Book に無ければ入れる。✕ の語は ✕ のままにする
    private func markUnsure(term: String, meaning: String) {
        if words.entry(for: term) == nil {
            words.saveAnswer(term: term, note: meaning, context: usageSentence(for: term), restoring: nil)
        }
        guard let entry = words.entry(for: term), entry.mastery != .notYet, entry.mastery != .unsure else { return }
        words.setMastery(.unsure, for: entry.id)
    }

    func isSaved(_ chunk: StudyChunk) -> Bool {
        words.entry(for: chunk.expression) != nil
    }

    // 抜き出した表現を Book から外す・戻す
    func toggleSaved(_ chunk: StudyChunk) {
        if isSaved(chunk) {
            removedEntries[chunk.id] = words.remove(term: chunk.expression)
        } else {
            words.saveAnswer(term: chunk.expression, note: chunk.meaning, context: usageSentence(for: chunk.expression), restoring: removedEntries[chunk.id])
            removedEntries[chunk.id] = nil
        }
    }

    // 訳はすぐ出したいので、覚える表現は訳が出きったあとに別に頼んで、出たものから Book に入れる。
    // もう Book にある単語は入れ直さない
    private func extract(source: String, translation: String) {
        state.isExtracting = true
        removedEntries = [:]
        let client = settings.makeClient()
        extractTask = Task {
            var raw = ""
            do {
                for try await piece in client.stream([ChatMessage(.user, Prompts.extraction(source: source, translation: translation))]) {
                    raw += piece
                }
            } catch {
                // 抜き出せなくても訳は出ているので、黙って諦める。翻訳の邪魔をしない
            }
            guard !Task.isCancelled else { return }
            let chunks = Prompts.splitChunks(raw).chunks
            for chunk in chunks {
                words.saveExtracted(term: chunk.expression, meaning: chunk.meaning, context: usageSentence(for: chunk.expression, in: source + "\n" + translation))
            }
            state.extracted = chunks
            state.isExtracting = false
        }
    }

    private func usageSentence(for expression: String, in text: String? = nil) -> String {
        Sentence.containing(expression, in: text ?? state.sourceText + "\n" + state.translation) ?? ""
    }

    // 画像の英文は、書き起こしが出てから段階の訳をもう1回頼む。段階の訳は AI が出した語句が英文にあるかを原文で確かめるので、
    // 書き起こしの前には頼めない。それまでは1回目の全文の訳を出しておき、段階の訳ができたら入れ替える。
    // 段階の訳に失敗しても、全文の訳はそのまま読めるので黙って諦める
    private func gradeTranscript(_ transcript: String, client: ChatClient) async throws {
        guard MixedTranslation.isEnglish(transcript) else { return }
        let known = words.knownTerms.filter { MixedTranslation.contains($0, in: transcript) }
        let system = ChatMessage(.system, Prompts.gradedTranslation(known: known))
        var done: [GradedTranslation] = []
        do {
            for part in GradedTranslation.parts(of: transcript) {
                var partRaw = ""
                for try await piece in client.stream([system, ChatMessage(.user, part)]) {
                    guard !Task.isCancelled else { return }
                    partRaw += piece
                }
                done.append(GradedTranslation.parse(partRaw, knownTerms: known, source: part))
            }
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let graded = GradedTranslation.joined(done, source: transcript)
        guard !graded.phrases.isEmpty else { return }
        state.graded = graded
        state.translation = graded.japanese
    }

    // 同じ文を同じ翻訳先で訳したことがあれば、AI に送らず履歴の訳を出す。force で必ず訳し直す
    func translate(force: Bool = false) {
        let typed = state.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.canTranslate else { return }
        recordReading()
        task?.cancel()
        extractTask?.cancel()
        state.error = nil
        state.extracted = []
        state.isExtracting = false
        state.graded = nil
        state.level = settings.state.englishLevel
        state.isRead = false
        state.askedTerms = []
        state.revealed = []
        let target = settings.state.target
        // 英文を日本語にするときは、覚えた表現を英語のまま残す。覚えた表現は日々変わるので、履歴の訳は使わない
        let known = words.knownTerms.filter { MixedTranslation.contains($0, in: typed) }
        let mixes = state.sourceImage == nil && target != .english && MixedTranslation.isEnglish(typed)
        if !mixes, !force, state.sourceImage == nil, let hit = history.cached(source: typed, target: target) {
            state.translation = hit.translation
            state.isTranslating = false
            state.isFromCache = true
            history.touch(hit)
            activity.record(.translated, title: hit.title)
            return
        }
        state.isFromCache = false
        state.translation = ""
        state.isTranslating = true
        let image = state.sourceImage
        let fillsSourceFromImage = image != nil && typed.isEmpty
        let client = settings.makeClient()
        let userMessage = ChatMessage(.user, typed.isEmpty ? "この画像を翻訳してください" : typed, images: image.map { [$0] } ?? [])

        task = Task {
            var raw = ""
            do {
                let messages: [ChatMessage]
                if mixes {
                    messages = [ChatMessage(.system, Prompts.gradedTranslation(known: known)), userMessage]
                } else {
                    messages = [ChatMessage(.system, Prompts.translation(target: target, hasImage: image != nil)), userMessage]
                }
                guard !Task.isCancelled else { return }
                if mixes {
                    // 長い英文は段落のまとまりごとに順に訳し、訳せた分から画面に出す
                    var done: [GradedTranslation] = []
                    for part in GradedTranslation.parts(of: typed) {
                        var partRaw = ""
                        for try await piece in client.stream([messages[0], ChatMessage(.user, part)]) {
                            guard !Task.isCancelled else { return }
                            partRaw += piece
                            let graded = GradedTranslation.joined(done + [GradedTranslation.parse(partRaw, knownTerms: known, source: part)], source: typed)
                            state.graded = graded
                            state.translation = graded.japanese
                        }
                        done.append(GradedTranslation.parse(partRaw, knownTerms: known, source: part))
                    }
                } else {
                    for try await chunk in client.stream(messages) {
                        // キャンセル前に届いていた分が、次の翻訳の表示を上書きしないようにする
                        guard !Task.isCancelled else { return }
                        raw += chunk
                        if image == nil {
                            state.translation = raw
                        } else {
                            let output = Prompts.splitImageOutput(raw)
                            if fillsSourceFromImage { state.sourceText = output.transcript }
                            state.translation = output.translation
                        }
                    }
                    if image != nil, target != .english {
                        try await gradeTranscript(Prompts.splitImageOutput(raw).transcript, client: client)
                    }
                }
                // キャンセルされたストリームは throw せずにループを抜けるので、ここで止める
                guard !Task.isCancelled else { return }
                state.isTranslating = false
                history.record(source: state.sourceText, translation: state.translation, image: image, target: target)
                activity.record(.translated, title: history.state.items.first?.title ?? "")
                extract(source: state.sourceText, translation: state.translation)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                state.isTranslating = false
                state.error = error.localizedDescription
            }
        }
    }
}
