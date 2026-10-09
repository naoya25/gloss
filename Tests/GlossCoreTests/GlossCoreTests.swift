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

@Test func oldWordsAndSettingsStillDecode() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let words = #"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","date":"2026-10-09T09:00:00Z","term":"take for granted","note":"当然と思う","context":"She took it for granted."}]"#
    let decoded = try decoder.decode([WordEntry].self, from: Data(words.utf8))
    #expect(decoded[0].flipCount == 0)
    #expect(decoded[0].masteryLevel == .notYet)
    #expect(decoded[0].text(for: .japanese) == "take for granted")

    let settings = #"{"engine":"openai","model":"m","jaiUserID":"","target":"auto"}"#
    let decodedSettings = try decoder.decode(AppSettings.self, from: Data(settings.utf8))
    #expect(decodedSettings.engine == .openai)
    #expect(decodedSettings.wordSort == .stale)
}

@Test func cardPairIsParsed() throws {
    let pair = try #require(Prompts.parseCardPair("EN: take for granted\nJA: 当然と思う\nEX: Don't take me for granted.\nEXJA: わたしを当たり前だと思わないで。"))
    #expect(pair.english == "take for granted")
    #expect(pair.japanese == "当然と思う")
    #expect(pair.example == "Don't take me for granted.")
    #expect(pair.exampleTranslation == "わたしを当たり前だと思わないで。")
    #expect(Prompts.parseCardPair("EN: a\nJA: あ")?.example == "")
    #expect(Prompts.parseCardPair("当然と思う") == nil)
}

@Test func wordsAreSortedForReview() {
    var old = WordEntry(term: "old", note: "", context: "")
    old.date = Date(timeIntervalSince1970: 0)
    var flipped = WordEntry(term: "flipped", note: "", context: "")
    flipped.recordFlip(at: Date(timeIntervalSince1970: 100))
    flipped.mastery = .known
    var unsure = WordEntry(term: "unsure", note: "", context: "")
    unsure.recordFlip(at: Date(timeIntervalSince1970: 50))
    unsure.recordFlip(at: Date(timeIntervalSince1970: 60))
    unsure.mastery = .unsure
    let words = [flipped, unsure, old]
    #expect(words.sorted(by: .stale).map(\.term) == ["old", "unsure", "flipped"])
    #expect(words.sorted(by: .fewestFlips).map(\.term) == ["old", "flipped", "unsure"])
    #expect(words.sorted(by: .mastery).map(\.term) == ["old", "unsure", "flipped"])
}

@Test func keychainAccountAndQuotingAreHandled() {
    let attributes = "keychain: \"/Users/me/Library/Keychains/login.keychain-db\"\n    \"acct\"<blob>=\"trapop\"\n    \"svce\"<blob>=\"trapop-jai\""
    #expect(Keychain.account(in: attributes) == "trapop")
    #expect(Keychain.account(in: "\"acct\"<blob>=<NULL>") == nil)
    #expect(Keychain.quote(#"a"b\c"#) == #""a\"b\\c""#)
}

@Test func keysWithControlCharactersAreRejected() {
    #expect(Keychain.isAcceptableKey("  sk-abc123\n"))
    #expect(!Keychain.isAcceptableKey("sk-abc\ndelete-generic-password -s trapop-jai"))
    #expect(!Keychain.isAcceptableKey("sk-abc\rdef"))
    #expect(!Keychain.isAcceptableKey("   "))
    #expect(!Keychain.setAPIKey("a\nb", service: "gloss-test-never-written"))
}

@Test func cardContentIsOnlyRequestedForTheSavingEngineUntilItFails() {
    var word = WordEntry(term: "run", note: "", context: "")
    #expect(!word.needsCardContent(for: .jai))
    word.engine = .jai
    #expect(word.needsCardContent(for: .jai))
    #expect(!word.needsCardContent(for: .openai))
    word.cardError = "HTTP 401"
    #expect(!word.needsCardContent(for: .jai))
}
