import AppKit
import AVFoundation
import GlossCore
import Observation

struct SpeechState {
    // 読み上げている単語。カードのボタンと Listen の両方で使う
    var speakingWordID: UUID?
    // テストの英文など、単語以外で読み上げている文
    var speakingText: String?
    var isListening = false
}

// 英語を Samantha の声で読み上げる。Listen では、単語 → 例文の順に Book を上から読み進める
@MainActor
@Observable
final class SpeechStore {
    private(set) var state = SpeechState()
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = SpeechStore.preferredVoice()
    private var task: Task<Void, Never>?

    func speak(_ word: WordEntry) {
        stop()
        task = Task { await read(word) }
    }

    func speak(_ text: String) {
        stop()
        state.speakingText = text
        task = Task {
            await say(text)
            if !Task.isCancelled { state.speakingText = nil }
        }
    }

    // 画面のどこでも、選んだ英語を読み上げる。選んだ文の取り方は、文字の欄ならその欄から、
    // それ以外(選べる Text など)はコピーを借りて読み、クリップボードは元に戻す
    func speakSelection() {
        guard let text = Self.selectedText(), let english = MixedTranslation.englishParts(of: text) else {
            NSSound.beep()
            return
        }
        speak(english)
    }

    private static func selectedText() -> String? {
        if let view = NSApp.keyWindow?.firstResponder as? NSTextView {
            let selected = view.selectedRanges.map { (view.string as NSString).substring(with: $0.rangeValue) }.joined(separator: " ")
            if !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return selected }
        }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let before = pasteboard.changeCount
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        guard pasteboard.changeCount != before else { return nil }
        let copied = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
        return copied
    }

    func listen(_ words: [WordEntry]) {
        stop()
        state.isListening = true
        task = Task {
            for word in words {
                guard !Task.isCancelled else { break }
                await read(word)
                try? await Task.sleep(for: .seconds(1.2))
            }
            if !Task.isCancelled { finish() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        state.speakingWordID = nil
        state.speakingText = nil
        state.isListening = false
    }

    private func read(_ word: WordEntry) async {
        state.speakingWordID = word.id
        await say(word.text(for: .english))
        if let example = word.example, !example.isEmpty, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.6))
            await say(example)
        }
        if !Task.isCancelled, !state.isListening { state.speakingWordID = nil }
    }

    private func say(_ text: String) async {
        guard !Task.isCancelled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let delegate = SpeechDelegate()
        synthesizer.delegate = delegate
        await withCheckedContinuation { continuation in
            delegate.onFinish = { continuation.resume() }
            synthesizer.speak(utterance)
        }
    }

    // 入っている Samantha のうち一番音のよいもの(同じ質なら super-compact より compact)。無ければアメリカ英語の標準の声
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let samantha = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.name.hasPrefix("Samantha") && $0.language == "en-US" }
            .max { rank($0) < rank($1) }
        return samantha ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        voice.quality.rawValue * 2 + (voice.identifier.contains("super-compact") ? 0 : 1)
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    // 止めたときも続きを待たせないよう、読み終わりと中断の両方で返す
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resume()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resume()
    }

    private func resume() {
        onFinish?()
        onFinish = nil
    }
}
