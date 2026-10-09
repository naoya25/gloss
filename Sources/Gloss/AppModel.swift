import AppKit
import GlossCore
import Observation

enum SidebarItem: Hashable {
    case current
    case words
    case history
}

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet { JSONFile<AppSettings>(AppPaths.settings).save(settings) }
    }
    private(set) var history: [HistoryItem]
    private(set) var words: [WordEntry]

    var sidebarSelection: SidebarItem? = .current {
        didSet { if let sidebarSelection, sidebarSelection != oldValue { route(to: sidebarSelection) } }
    }
    private(set) var showsWords = false
    private(set) var showsHistory = false

    // 並び順は単語帳を開いたときと並び替えを変えたときだけ決め直す。
    // めくるたびに並べ直すと、開いたカードが目の前から逃げるため
    private(set) var cardOrder: [UUID] = []
    private(set) var openCardID: UUID?
    private var isFillingCardPairs = false
    // 今の語句について自動保存を済ませたか、ユーザーが外したか。済んでいたら回答のたびに足し直さない
    private var focusAutoSaveHandled = false
    // 外した直後に戻せるよう、外した単語を学習記録ごと取っておく
    private var removedFocusEntry: WordEntry?

    var sourceText = ""
    private(set) var sourceImage: Data?
    private(set) var translation = ""
    private(set) var isTranslating = false
    private(set) var translationError: String?

    private(set) var selection = ""
    var isAskOpen = false
    private(set) var focus = ""
    private(set) var thread: [ChatMessage] = []
    var askDraft = ""
    private(set) var isAsking = false
    private(set) var askError: String?
    // 質問の文脈。翻訳画面では原文と訳文、カードから聞くときは保存した用例と説明
    private var askSource = ""
    private var askTranslation = ""

    private var translateTask: Task<Void, Never>?
    private var askTask: Task<Void, Never>?

    init() {
        settings = JSONFile<AppSettings>(AppPaths.settings).load()
            ?? AppSettings.importingTraPoP(from: AppPaths.traPoPConfig)
        history = JSONFile<[HistoryItem]>(AppPaths.history).load() ?? []
        words = JSONFile<[WordEntry]>(AppPaths.words).load() ?? []
    }

    var canTranslate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceImage != nil
    }

    var focusWord: WordEntry? {
        words.first { $0.term.caseInsensitiveCompare(focus) == .orderedSame }
    }

    var isFocusSaved: Bool {
        words.contains { $0.term.caseInsensitiveCompare(focus) == .orderedSame }
    }

    // MARK: Translation

    func newTranslation() {
        translateTask?.cancel()
        sourceText = ""
        sourceImage = nil
        translation = ""
        translationError = nil
        isTranslating = false
        selection = ""
        sidebarSelection = .current
        showsWords = false
        showsHistory = false
    }

    func setImage(_ data: Data) {
        sourceImage = data
        translate()
    }

    func removeImage() {
        sourceImage = nil
    }

    func didPasteText() {
        translate()
    }

    func translate() {
        let typed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canTranslate else { return }
        translateTask?.cancel()
        translation = ""
        translationError = nil
        isTranslating = true
        let image = sourceImage
        let fillsSourceFromImage = image != nil && typed.isEmpty
        let client = makeClient()
        let messages = [
            ChatMessage(.system, Prompts.translation(target: settings.target, hasImage: image != nil)),
            ChatMessage(.user, typed.isEmpty ? "この画像を翻訳してください" : typed, images: image.map { [$0] } ?? []),
        ]

        translateTask = Task {
            var raw = ""
            do {
                for try await chunk in client.stream(messages) {
                    // キャンセル前に届いていた分が、次の翻訳の表示を上書きしないようにする
                    guard !Task.isCancelled else { return }
                    raw += chunk
                    if image == nil {
                        translation = raw
                    } else {
                        let output = Prompts.splitImageOutput(raw)
                        if fillsSourceFromImage { sourceText = output.transcript }
                        translation = output.translation
                    }
                }
                // キャンセルされたストリームは throw せずにループを抜けるので、ここで止める
                guard !Task.isCancelled else { return }
                isTranslating = false
                recordHistory(image: image)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                isTranslating = false
                translationError = error.localizedDescription
            }
        }
    }

    private func recordHistory(image: Data?) {
        guard !translation.isEmpty else { return }
        var imageFile: String?
        if let image {
            let name = "\(UUID().uuidString).jpg"
            try? FileManager.default.createDirectory(at: AppPaths.images, withIntermediateDirectories: true)
            if (try? image.write(to: AppPaths.images.appendingPathComponent(name))) != nil {
                imageFile = name
            }
        }
        history.insert(HistoryItem(source: sourceText, translation: translation, imageFile: imageFile), at: 0)
        history = Array(history.prefix(300))
        JSONFile<[HistoryItem]>(AppPaths.history).save(history)
    }

    func deleteHistory(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        if let file = item.imageFile {
            try? FileManager.default.removeItem(at: AppPaths.images.appendingPathComponent(file))
        }
        JSONFile<[HistoryItem]>(AppPaths.history).save(history)
    }

    // 履歴の一覧で選んだ翻訳を、翻訳画面に戻して開く
    func openHistory(_ item: HistoryItem) {
        translateTask?.cancel()
        isTranslating = false
        translationError = nil
        sourceText = item.source
        translation = item.translation
        sourceImage = item.imageFile.flatMap { try? Data(contentsOf: AppPaths.images.appendingPathComponent($0)) }
        selection = ""
        sidebarSelection = .current
    }

    private func route(to item: SidebarItem) {
        switch item {
        case .current:
            showsWords = false
            showsHistory = false
        case .words:
            showsWords = true
            showsHistory = false
            openCardID = nil
            refreshCardOrder()
            fillCardPairs()
        case .history:
            showsWords = false
            showsHistory = true
        }
    }

    // MARK: Asking

    func select(_ text: String) {
        selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 文や段落ごと選んだときは質問しない。調べたい語句ではなく、コピーなどのための選択とみなす
    static let maxMouseSelectionLength = 60

    func askAboutMouseSelection(_ text: String) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, phrase.count <= Self.maxMouseSelectionLength,
              !phrase.contains(where: \.isNewline), phrase != focus
        else { return }
        selection = phrase
        askAboutSelection()
    }

    func askAboutSelection() {
        guard !selection.isEmpty else { return }
        askTask?.cancel()
        focus = selection
        thread = []
        askError = nil
        askSource = sourceText
        askTranslation = translation
        focusAutoSaveHandled = false
        removedFocusEntry = nil
        isAskOpen = true
        send(Prompts.quickQuestions[0].question(about: focus))
    }

    // カードから聞くときは、保存済みの説明を最初の答えとして並べて、続きから質問できるようにする。
    // もう単語帳にあるので、追加の答えで説明を上書きしない
    func askAboutWord(_ id: UUID) {
        guard let word = words.first(where: { $0.id == id }) else { return }
        askTask?.cancel()
        isAsking = false
        focus = word.term
        askError = nil
        askSource = word.context
        askTranslation = ""
        thread = word.note.isEmpty ? [] : [
            ChatMessage(.user, Prompts.quickQuestions[0].question(about: word.term)),
            ChatMessage(.assistant, word.note),
        ]
        focusAutoSaveHandled = true
        removedFocusEntry = nil
        isAskOpen = true
        if thread.isEmpty { send(Prompts.quickQuestions[0].question(about: focus)) }
    }

    func clearAsk() {
        askTask?.cancel()
        isAsking = false
        focus = ""
        thread = []
        askError = nil
        askDraft = ""
    }

    func sendDraft() {
        let question = askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !focus.isEmpty else { return }
        askDraft = ""
        send(question)
    }

    func send(_ question: String) {
        askTask?.cancel()
        askError = nil
        let context = ChatMessage(.system, Prompts.tutor(source: askSource, translation: askTranslation, focus: focus))
        let usage = usageSentence()
        thread.append(ChatMessage(.user, question))
        let request = [context] + thread
        thread.append(ChatMessage(.assistant, ""))
        let answerIndex = thread.count - 1
        isAsking = true
        let client = makeClient()

        askTask = Task {
            do {
                for try await chunk in client.stream(request) {
                    guard !Task.isCancelled, thread.indices.contains(answerIndex) else { return }
                    thread[answerIndex].text += chunk
                }
                // その語句への答えが最後まで出たら、単語帳に1回だけ自動で入れる
                if !Task.isCancelled, !focusAutoSaveHandled, !thread[answerIndex].text.isEmpty {
                    focusAutoSaveHandled = true
                    saveFocus(note: thread[answerIndex].text, context: usage)
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { askError = error.localizedDescription }
            }
            // 次の質問が始まっているときに、その isAsking を落とさない
            guard !Task.isCancelled else { return }
            isAsking = false
        }
    }

    private func usageSentence() -> String {
        Sentence.containing(focus, in: askSource) ?? Sentence.containing(focus, in: askTranslation) ?? ""
    }

    // パネルのボタンで戻すときは、出きった最後の答えを説明として使う
    func saveFocus() {
        let lastAnswer = thread.last { $0.role == .assistant && !$0.text.isEmpty }?.text
        guard let note = lastAnswer else { return }
        focusAutoSaveHandled = true
        saveFocus(note: note, context: usageSentence())
    }

    private func saveFocus(note: String, context: String) {
        if let index = words.firstIndex(where: { $0.term.caseInsensitiveCompare(focus) == .orderedSame }) {
            words[index].note = note
            if !context.isEmpty { words[index].context = context }
        } else if var restored = removedFocusEntry {
            restored.note = note
            if !context.isEmpty { restored.context = context }
            words.insert(restored, at: 0)
        } else {
            var entry = WordEntry(term: focus, note: note, context: context)
            entry.engine = settings.engine
            words.insert(entry, at: 0)
        }
        removedFocusEntry = nil
        saveWords()
        fillCardPairs()
    }

    func removeFocus() {
        focusAutoSaveHandled = true
        removedFocusEntry = words.first { $0.term.caseInsensitiveCompare(focus) == .orderedSame }
        words.removeAll { $0.term.caseInsensitiveCompare(focus) == .orderedSame }
        saveWords()
    }

    // MARK: Flashcards

    var orderedWords: [WordEntry] {
        let byID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let ordered = cardOrder.compactMap { byID[$0] }
        let known = Set(cardOrder)
        let unordered = words.filter { !known.contains($0.id) }
        return unordered + ordered
    }

    func setWordSort(_ order: WordSort) {
        settings.wordSort = order
        openCardID = nil
        refreshCardOrder()
    }

    func refreshCardOrder() {
        cardOrder = words.sorted(by: settings.wordSort).map(\.id)
    }

    // 開いているカードをもう一度押すと閉じる。別のカードを押すと、前のカードは表に戻る
    func flipCard(_ id: UUID) {
        if openCardID == id {
            openCardID = nil
            // パネルを閉じると詳細の幅が変わってカードがずれるので、開いたまま中身だけ消す
            clearAsk()
            return
        }
        openCardID = id
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        words[index].recordFlip()
        saveWords()
        // めくったカードの詳しい説明を右のパネルに出して、そのまま続きを質問できるようにする
        askAboutWord(id)
    }

    func setMastery(_ mastery: Mastery, for id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        words[index].mastery = mastery
        saveWords()
    }

    func deleteWord(_ id: UUID) {
        words.removeAll { $0.id == id }
        if openCardID == id { openCardID = nil }
        saveWords()
    }

    // カードの訳と例文を、作り直すとユーザーが決めた単語は今のエンジンで作る
    func regenerateCard(_ id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        words[index].cardError = nil
        words[index].engine = settings.engine
        saveWords()
        fillCardPairs()
    }

    // カードに使う短い英語・日本語と例文を、まだ無い単語の分だけ1つずつ作る。
    // 単語を保存したときと同じエンジンの分だけ送る。別のエンジンに過去の文を勝手に送らないため
    func fillCardPairs() {
        guard !isFillingCardPairs else { return }
        isFillingCardPairs = true
        let engine = settings.engine
        let client = makeClient()
        Task {
            defer { isFillingCardPairs = false }
            while let word = words.first(where: { $0.needsCardContent(for: engine) }) {
                var raw = ""
                var failure: String?
                do {
                    let messages = [ChatMessage(.user, Prompts.cardPair(term: word.term, context: word.context))]
                    for try await chunk in client.stream(messages) { raw += chunk }
                } catch {
                    failure = error.localizedDescription
                }
                guard let index = words.firstIndex(where: { $0.id == word.id }) else { continue }
                if let pair = failure == nil ? Prompts.parseCardPair(raw) : nil {
                    words[index].english = pair.english
                    words[index].japanese = pair.japanese
                    words[index].example = pair.example
                    words[index].exampleTranslation = pair.exampleTranslation
                }
                // 失敗や例文の欠けは記録して、開くたびに頼み直さない。右クリックの「作り直す」で消える
                if !words[index].isCardComplete {
                    words[index].cardError = failure ?? "AI の答えから訳と例文を読み取れませんでした"
                }
                saveWords()
            }
        }
    }

    private func saveWords() {
        JSONFile<[WordEntry]>(AppPaths.words).save(words)
    }

    private func makeClient() -> ChatClient {
        ChatClient(engine: settings.engine, model: settings.model, userID: settings.jaiUserID)
    }
}
