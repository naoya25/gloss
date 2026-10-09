import Foundation
import GlossCore
import Observation

struct WordsState {
    var words: [WordEntry] = []
    // 並び順は単語帳を開いたときと並び替えを変えたときだけ決め直す。
    // めくるたびに並べ直すと、開いたカードが目の前から逃げるため
    var cardOrder: [UUID] = []
    var openCardID: UUID?
}

@MainActor
@Observable
final class WordsStore {
    private(set) var state: WordsState
    private let settings: SettingsStore
    private var isFillingCardPairs = false

    init(settings: SettingsStore) {
        self.settings = settings
        state = WordsState(words: JSONFile<[WordEntry]>(AppPaths.words).load() ?? [])
    }

    var orderedWords: [WordEntry] {
        let byID = Dictionary(uniqueKeysWithValues: state.words.map { ($0.id, $0) })
        let ordered = state.cardOrder.compactMap { byID[$0] }
        let known = Set(state.cardOrder)
        let unordered = state.words.filter { !known.contains($0.id) }
        return unordered + ordered
    }

    func entry(for term: String) -> WordEntry? {
        state.words.first { $0.term.caseInsensitiveCompare(term) == .orderedSame }
    }

    func didOpen() {
        state.openCardID = nil
        refreshCardOrder()
        fillCardPairs()
    }

    func setSort(_ order: WordSort) {
        settings.setWordSort(order)
        state.openCardID = nil
        refreshCardOrder()
    }

    // 開いているカードをもう一度押すと閉じる。別のカードを押すと、前のカードは表に戻る。
    // 押したあとにそのカードが開いているかを返す
    @discardableResult
    func flip(_ id: UUID) -> Bool {
        if state.openCardID == id {
            state.openCardID = nil
            return false
        }
        state.openCardID = id
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return true }
        state.words[index].recordFlip()
        save()
        return true
    }

    func setMastery(_ mastery: Mastery, for id: UUID) {
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return }
        state.words[index].mastery = mastery
        save()
    }

    func delete(_ id: UUID) {
        state.words.removeAll { $0.id == id }
        if state.openCardID == id { state.openCardID = nil }
        save()
    }

    // 質問の答えを単語帳に入れる。外した直後の単語を戻すときは、学習記録ごと戻す
    func saveAnswer(term: String, note: String, context: String, restoring removed: WordEntry?) {
        if let index = state.words.firstIndex(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) {
            state.words[index].note = note
            if !context.isEmpty { state.words[index].context = context }
        } else if var restored = removed {
            restored.note = note
            if !context.isEmpty { restored.context = context }
            state.words.insert(restored, at: 0)
        } else {
            var entry = WordEntry(term: term, note: note, context: context)
            entry.engine = settings.state.engine
            state.words.insert(entry, at: 0)
        }
        save()
        fillCardPairs()
    }

    func remove(term: String) -> WordEntry? {
        let removed = entry(for: term)
        state.words.removeAll { $0.term.caseInsensitiveCompare(term) == .orderedSame }
        save()
        return removed
    }

    // カードの訳と例文を、作り直すとユーザーが決めた単語は今のエンジンで作る
    func regenerate(_ id: UUID) {
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return }
        state.words[index].cardError = nil
        state.words[index].engine = settings.state.engine
        save()
        fillCardPairs()
    }

    private func refreshCardOrder() {
        state.cardOrder = state.words.sorted(by: settings.state.wordSort).map(\.id)
    }

    // カードに使う短い英語・日本語と例文を、まだ無い単語の分だけ1つずつ作る。
    // 単語を保存したときと同じエンジンの分だけ送る。別のエンジンに過去の文を勝手に送らないため
    private func fillCardPairs() {
        guard !isFillingCardPairs else { return }
        isFillingCardPairs = true
        let engine = settings.state.engine
        let client = settings.makeClient()
        Task {
            defer { isFillingCardPairs = false }
            while let word = state.words.first(where: { $0.needsCardContent(for: engine) }) {
                var raw = ""
                var failure: String?
                do {
                    let messages = [ChatMessage(.user, Prompts.cardPair(term: word.term, context: word.context))]
                    for try await chunk in client.stream(messages) { raw += chunk }
                } catch {
                    failure = error.localizedDescription
                }
                guard let index = state.words.firstIndex(where: { $0.id == word.id }) else { continue }
                if let pair = failure == nil ? Prompts.parseCardPair(raw) : nil {
                    state.words[index].english = pair.english
                    state.words[index].japanese = pair.japanese
                    state.words[index].example = pair.example
                    state.words[index].exampleTranslation = pair.exampleTranslation
                }
                // 失敗や例文の欠けは記録して、開くたびに頼み直さない。右クリックの「作り直す」で消える
                if !state.words[index].isCardComplete {
                    state.words[index].cardError = failure ?? "AI の答えから訳と例文を読み取れませんでした"
                }
                save()
            }
        }
    }

    private func save() {
        JSONFile<[WordEntry]>(AppPaths.words).save(state.words)
    }
}
