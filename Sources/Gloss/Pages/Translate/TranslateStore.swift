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
        task?.cancel()
        extractTask?.cancel()
        state = TranslateState()
    }

    // 履歴の一覧で選んだ翻訳を開く
    func open(_ item: HistoryItem, image: Data?) {
        task?.cancel()
        extractTask?.cancel()
        state = TranslateState(sourceText: item.source, sourceImage: image, translation: item.translation)
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

    // 同じ文を同じ翻訳先で訳したことがあれば、AI に送らず履歴の訳を出す。force で必ず訳し直す
    func translate(force: Bool = false) {
        let typed = state.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.canTranslate else { return }
        task?.cancel()
        extractTask?.cancel()
        state.error = nil
        state.extracted = []
        state.isExtracting = false
        let target = settings.state.target
        if !force, state.sourceImage == nil, let hit = history.cached(source: typed, target: target) {
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
        let messages = [
            ChatMessage(.system, Prompts.translation(target: target, hasImage: image != nil)),
            ChatMessage(.user, typed.isEmpty ? "この画像を翻訳してください" : typed, images: image.map { [$0] } ?? []),
        ]

        task = Task {
            var raw = ""
            do {
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
