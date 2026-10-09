import Foundation
import Testing
@testable import GlossCore

@Test func sseDeltaIsExtracted() {
    let line = #"data: {"choices":[{"delta":{"content":"こんにちは"}}]}"#
    #expect(SSEEvent.parse(line: line) == .delta("こんにちは"))
}

@Test func sseDoneAndNoiseAreRecognized() {
    #expect(SSEEvent.parse(line: "data: [DONE]") == .done)
    #expect(SSEEvent.parse(line: ": keep-alive") == .ignore)
    #expect(SSEEvent.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignore)
}

@Test func imageMessageIsSentAsContentParts() throws {
    let message = ChatMessage(.user, "訳して", images: [Data([0xFF, 0xD8])])
    let body = ChatClient.body(model: "m", messages: [message])
    let messages = try #require(body["messages"] as? [[String: Any]])
    let parts = try #require(messages[0]["content"] as? [[String: Any]])
    #expect(parts[0]["type"] as? String == "text")
    let imageURL = try #require(parts[1]["image_url"] as? [String: String])
    #expect(imageURL["url"] == "data:image/jpeg;base64,/9g=")
}

@Test func textMessageIsSentAsPlainString() throws {
    let body = ChatClient.body(model: "m", messages: [ChatMessage(.user, "hi")])
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages[0]["content"] as? String == "hi")
    #expect(body["stream"] as? Bool == true)
}

@Test func jaiURLCarriesUserIDAndRequiresIt() throws {
    let url = try Engine.jai.chatURL(userID: "me@example.com")
    #expect(url.absoluteString == "https://api.japan-ai.co.jp/v1/chat/completions?userId=me@example.com")
    #expect(throws: GlossError.missingUserID) { try Engine.jai.chatURL(userID: " ") }
}

@Test func imageOutputSplitsTranscriptAndTranslation() {
    let raw = "Hello world.\nSee you.\n=====\nこんにちは世界。\nまたね。"
    let output = Prompts.splitImageOutput(raw)
    #expect(output.transcript == "Hello world.\nSee you.")
    #expect(output.translation == "こんにちは世界。\nまたね。")
}

@Test func imageOutputBeforeSeparatorIsAllTranscript() {
    #expect(Prompts.splitImageOutput("Hello wor") == .init(transcript: "Hello wor", translation: ""))
}

@Test func sentenceAroundFocusIsExtracted() {
    let text = "I was tired. She took it for granted that I'd come. Then we left."
    #expect(Sentence.containing("for granted", in: text) == "She took it for granted that I'd come.")
    #expect(Sentence.containing("missing", in: text) == nil)
}

@Test func translationPromptForcesTargetLanguage() {
    #expect(Prompts.translation(target: .japanese, hasImage: false).contains("必ず日本語で出力"))
    #expect(Prompts.translation(target: .auto, hasImage: true).contains(Prompts.transcriptSeparator))
}

@Test func traPoPSettingsAreImported() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trapop-\(UUID()).json")
    try #"{"engine_choice":"jai","model_override":"gemini-3.1-flash-lite","jai_user_id":"a@b.c"}"#
        .write(to: url, atomically: true, encoding: .utf8)
    let settings = AppSettings.importingTraPoP(from: url)
    #expect(settings.engine == .jai)
    #expect(settings.model == "gemini-3.1-flash-lite")
    #expect(settings.jaiUserID == "a@b.c")
}
