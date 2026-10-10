import Foundation
import GlossCore
import Observation

struct WordsState {
    var words: [WordEntry] = []
    // 並び順は単語帳を開いたときと並び替えを変えたときだけ決め直す。
    // めくるたびに並べ直すと、開いたカードが目の前から逃げるため
    var cardOrder: [UUID] = []
    var openCardID: UUID?
    var sync: SyncStatus = .off
}

enum SyncStatus: Equatable {
    case off
    case syncing
    case synced(Date)
    case failed(String)
}

@MainActor
@Observable
final class WordsStore {
    private(set) var state: WordsState
    private let settings: SettingsStore
    private let activity: ActivityStore
    private var isFillingCardPairs = false
    // words.json は Cloudflare から取ってきた単語の控え。電波が無いときもこれで動く
    private var ledger: SyncLedger
    private var isSyncing = false
    private var syncAgain = false
    private var pushTask: Task<Void, Never>?

    init(settings: SettingsStore, activity: ActivityStore) {
        self.settings = settings
        self.activity = activity
        let words = JSONFile<[WordEntry]>(AppPaths.words).load() ?? []
        state = WordsState(words: words)
        ledger = JSONFile<SyncLedger>(AppPaths.sync).load() ?? .initial(for: words)
        sync()
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
        sync()
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
        activity.record(.cardFlipped, title: state.words[index].term)
        commit(id)
        return true
    }

    // 単語テストの採点。めくったときと同じく、見た回数と日も進める
    func recordQuizAnswer(_ id: UUID, mastery: Mastery) {
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return }
        state.words[index].mastery = mastery
        state.words[index].recordFlip()
        commit(id)
    }

    func setMastery(_ mastery: Mastery, for id: UUID) {
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return }
        state.words[index].mastery = mastery
        commit(id)
    }

    func delete(_ id: UUID) {
        state.words.removeAll { $0.id == id }
        if state.openCardID == id { state.openCardID = nil }
        commit(id)
    }

    // 質問の答えを単語帳に入れる。外した直後の単語を戻すときは、学習記録ごと戻す
    func saveAnswer(term: String, note: String, context: String, restoring removed: WordEntry?) {
        if let index = state.words.firstIndex(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) {
            state.words[index].note = note
            if !context.isEmpty { state.words[index].context = context }
            commit(state.words[index].id)
        } else if var restored = removed {
            restored.note = note
            if !context.isEmpty { restored.context = context }
            state.words.insert(restored, at: 0)
            commit(restored.id)
        } else {
            var entry = WordEntry(term: term, note: note, context: context)
            entry.engine = settings.state.engine
            state.words.insert(entry, at: 0)
            activity.record(.wordSaved, title: term)
            commit(entry.id)
        }
        fillCardPairs()
    }

    func remove(term: String) -> WordEntry? {
        let matches = state.words.filter { $0.term.caseInsensitiveCompare(term) == .orderedSame }
        state.words.removeAll { $0.term.caseInsensitiveCompare(term) == .orderedSame }
        commit(matches.map(\.id))
        return matches.first
    }

    // カードの訳と例文を、作り直すとユーザーが決めた単語は今のエンジンで作る
    func regenerate(_ id: UUID) {
        guard let index = state.words.firstIndex(where: { $0.id == id }) else { return }
        state.words[index].cardError = nil
        state.words[index].engine = settings.state.engine
        commit(id)
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
                    state.words[index].cardError = failure ?? "Couldn't read the translation and example from the AI's answer"
                }
                commit(word.id)
            }
        }
    }

    // Cloudflare に送れていない変更を送ってから、ほかの Mac が書いた分を取ってくる
    func sync() {
        guard let client = settings.makeSyncClient() else {
            state.sync = .off
            return
        }
        guard !isSyncing else {
            syncAgain = true
            return
        }
        isSyncing = true
        state.sync = .syncing
        Task {
            defer { isSyncing = false }
            do {
                repeat {
                    syncAgain = false
                    try await pushPending(with: client)
                    try await pullChanges(with: client)
                } while syncAgain
                state.sync = .synced(.now)
            } catch {
                state.sync = .failed(error.localizedDescription)
            }
        }
    }

    private func pushPending(with client: SyncClient) async throws {
        let rows = ledger.rows(from: state.words)
        for start in stride(from: 0, to: rows.count, by: SyncClient.maxRowsPerPush) {
            let batch = Array(rows[start..<min(start + SyncClient.maxRowsPerPush, rows.count)])
            try await client.push(batch)
            ledger.didPush(batch)
            saveLedger()
        }
    }

    private func pullChanges(with client: SyncClient) async throws {
        var hasMore = true
        while hasMore {
            let page = try await client.pull(since: ledger.cursor)
            state.words = WordSync.merge(state.words, with: page.words, ledger: ledger)
            ledger.cursor = page.cursor
            hasMore = page.hasMore
            saveWords()
            saveLedger()
        }
        if let open = state.openCardID, !state.words.contains(where: { $0.id == open }) {
            state.openCardID = nil
        }
        fillCardPairs()
    }

    private func commit(_ id: UUID) {
        commit([id])
    }

    // 書き換えた単語に時刻を付けて控えに保存し、少し待ってまとめて Cloudflare に送る
    private func commit(_ ids: [UUID]) {
        let now = Date()
        for id in ids {
            if let index = state.words.firstIndex(where: { $0.id == id }) {
                state.words[index].updatedAt = now
            }
            ledger.markChanged(id, at: now)
        }
        saveWords()
        saveLedger()
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    private func saveWords() {
        JSONFile<[WordEntry]>(AppPaths.words).save(state.words)
    }

    private func saveLedger() {
        JSONFile<SyncLedger>(AppPaths.sync).save(ledger)
    }
}
