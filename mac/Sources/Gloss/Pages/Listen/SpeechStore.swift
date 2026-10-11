import AVFoundation
import GlossCore
import Observation

struct SpeechState {
    // 読み上げている単語。カードのボタンと Listen の両方で使う
    var speakingWordID: UUID?
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
