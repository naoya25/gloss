import AppKit
import GlossCore
import Observation

enum SidebarItem: Hashable {
    case current
    case words
    case history(UUID)
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
                    raw += chunk
                    if image == nil {
                        translation = raw
                    } else {
                        let output = Prompts.splitImageOutput(raw)
                        if fillsSourceFromImage { sourceText = output.transcript }
                        translation = output.translation
                    }
                }
                isTranslating = false
                recordHistory(image: image)
            } catch is CancellationError {
            } catch {
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
        if sidebarSelection == .history(item.id) { newTranslation() }
    }

    private func route(to item: SidebarItem) {
        switch item {
        case .current:
            showsWords = false
        case .words:
            showsWords = true
        case .history(let id):
            showsWords = false
            guard let entry = history.first(where: { $0.id == id }) else { return }
            translateTask?.cancel()
            isTranslating = false
            translationError = nil
            sourceText = entry.source
            translation = entry.translation
            sourceImage = entry.imageFile.flatMap { try? Data(contentsOf: AppPaths.images.appendingPathComponent($0)) }
            selection = ""
        }
    }

    // MARK: Asking

    func select(_ text: String) {
        selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func askAboutSelection() {
        guard !selection.isEmpty else { return }
        askTask?.cancel()
        focus = selection
        thread = []
        askError = nil
        isAskOpen = true
        send(Prompts.quickQuestions[0].question(about: focus))
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
        let context = ChatMessage(.system, Prompts.tutor(source: sourceText, translation: translation, focus: focus))
        thread.append(ChatMessage(.user, question))
        let request = [context] + thread
        thread.append(ChatMessage(.assistant, ""))
        let answerIndex = thread.count - 1
        isAsking = true
        let client = makeClient()

        askTask = Task {
            do {
                for try await chunk in client.stream(request) {
                    guard thread.indices.contains(answerIndex) else { return }
                    thread[answerIndex].text += chunk
                }
            } catch is CancellationError {
            } catch {
                askError = error.localizedDescription
            }
            isAsking = false
        }
    }

    func saveFocus() {
        guard let answer = thread.first(where: { $0.role == .assistant && !$0.text.isEmpty })?.text else { return }
        let context = Sentence.containing(focus, in: sourceText) ?? Sentence.containing(focus, in: translation) ?? ""
        if let index = words.firstIndex(where: { $0.term.caseInsensitiveCompare(focus) == .orderedSame }) {
            words[index].note = answer
            words[index].context = context
        } else {
            words.insert(WordEntry(term: focus, note: answer, context: context), at: 0)
        }
        JSONFile<[WordEntry]>(AppPaths.words).save(words)
    }

    func deleteWords(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        JSONFile<[WordEntry]>(AppPaths.words).save(words)
    }

    private func makeClient() -> ChatClient {
        ChatClient(engine: settings.engine, model: settings.model, userID: settings.jaiUserID)
    }
}
