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

@Test func studyChunksAreSplitFromTheAnswer() {
    let raw = """
    stop by で「立ち寄る」という句動詞です。to は welcome to に続く不定詞です。
    CHUNK: stop by | 立ち寄る
    CHUNK: grab a drink | 飲み物を手に取る
    CHUNK: Stop By | 重複
    """
    let result = Prompts.splitChunks(raw)
    #expect(result.text == "stop by で「立ち寄る」という句動詞です。to は welcome to に続く不定詞です。")
    #expect(result.chunks == [
        StudyChunk(expression: "stop by", meaning: "立ち寄る"),
        StudyChunk(expression: "grab a drink", meaning: "飲み物を手に取る"),
    ])
}

@Test func noChunkAndPartialChunkLinesAreHidden() {
    #expect(Prompts.splitChunks("説明です。\nCHUNK: なし").chunks.isEmpty)
    #expect(Prompts.splitChunks("説明です。\nCHUNK: なし").text == "説明です。")
    #expect(Prompts.splitChunks("説明です。\nCHU").text == "説明です。")
    #expect(Prompts.splitChunks("説明です。\nCHUNK: sto").text == "説明です。")
}

@Test func historyMatchesOnlyTheSameTextAndTarget() throws {
    let item = HistoryItem(source: "  Stop by anytime.\n", translation: "いつでも寄って", target: .japanese)
    #expect(item.matches(source: "Stop by anytime.", target: .japanese))
    #expect(!item.matches(source: "Stop by anytime!", target: .japanese))
    #expect(!item.matches(source: "Stop by anytime.", target: .english))
    #expect(!HistoryItem(source: "a", translation: "b", imageFile: "x.jpg").matches(source: "a", target: .auto))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let old = #"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","date":"2026-10-09T09:00:00Z","source":"hi","translation":"やあ"}]"#
    let decoded = try decoder.decode([HistoryItem].self, from: Data(old.utf8))
    #expect(decoded[0].matches(source: "hi", target: .auto))
}

private func word(_ term: String, updatedAt millis: Int64? = nil) -> WordEntry {
    var entry = WordEntry(term: term, note: "", context: "")
    entry.updatedAt = millis.map(WordSync.date)
    return entry
}

@Test func newerRemoteWordReplacesLocalAndOlderIsIgnored() {
    let local = word("stop by", updatedAt: 2_000)
    var newer = local
    newer.note = "立ち寄る"
    var older = local
    older.note = "古い"
    let merged = WordSync.merge([local], with: [SyncRow(id: local.id.uuidString, updatedAt: 3_000, deleted: false, data: newer)], ledger: SyncLedger())
    #expect(merged.first?.note == "立ち寄る")
    #expect(merged.first?.updatedAt == WordSync.date(3_000))
    let kept = WordSync.merge([local], with: [SyncRow(id: local.id.uuidString, updatedAt: 1_000, deleted: false, data: older)], ledger: SyncLedger())
    #expect(kept == [local])
}

@Test func remoteDeletionRemovesWordUnlessLocalChangeIsNewer() {
    let local = word("grab a drink", updatedAt: 1_000)
    let deletion = SyncRow(id: local.id.uuidString, updatedAt: 2_000, deleted: true, data: nil)
    #expect(WordSync.merge([local], with: [deletion], ledger: SyncLedger()).isEmpty)
    var ledger = SyncLedger()
    ledger.markChanged(local.id, at: WordSync.date(5_000))
    #expect(WordSync.merge([local], with: [deletion], ledger: ledger).count == 1)
}

@Test func locallyDeletedWordIsNotRevivedByOlderRemoteCopy() {
    let gone = word("let me know", updatedAt: 1_000)
    var ledger = SyncLedger()
    ledger.markChanged(gone.id, at: WordSync.date(4_000))
    let stale = SyncRow(id: gone.id.uuidString, updatedAt: 3_000, deleted: false, data: gone)
    #expect(WordSync.merge([], with: [stale], ledger: ledger).isEmpty)
    #expect(ledger.rows(from: []) == [SyncRow(id: gone.id.uuidString, updatedAt: 4_000, deleted: true, data: nil)])
}

@Test func wordChangedDuringPushStaysPending() {
    let entry = word("heads up")
    var ledger = SyncLedger()
    ledger.markChanged(entry.id, at: WordSync.date(1_000))
    let sent = ledger.rows(from: [entry])
    ledger.markChanged(entry.id, at: WordSync.date(2_000))
    ledger.didPush(sent)
    #expect(ledger.pending[entry.id.uuidString] == 2_000)
    ledger.didPush(ledger.rows(from: [entry]))
    #expect(ledger.pending.isEmpty)
}

@Test func firstSyncSendsEveryWordWithItsLastTouch() {
    var reviewed = word("FYI")
    reviewed.lastReviewed = WordSync.date(7_000)
    let ledger = SyncLedger.initial(for: [reviewed])
    #expect(ledger.pending[reviewed.id.uuidString] == 7_000)
}

@Test func syncURLMustBeHTTPS() {
    #expect(throws: SyncError.badURL) { try SyncClient(baseURL: "http://example.com", token: "t") }
    #expect((try? SyncClient(baseURL: " https://gloss-sync.example.workers.dev ", token: "t")) != nil)
}

@Test func wordQuizIgnoresCaseSpacingAndPunctuation() {
    var entry = WordEntry(term: "let me know", note: "", context: "")
    entry.english = "Let me know"
    #expect(WordQuiz.isCorrect("  let  me KNOW. ", for: entry))
    #expect(WordQuiz.isCorrect("let me know!", for: entry))
    #expect(!WordQuiz.isCorrect("let me", for: entry))
    #expect(!WordQuiz.isCorrect("", for: entry))
}

@Test func wordTestReviewIsParsed() {
    let raw = """
    1: O | 同じ意味
    2: ? | 名詞ではなく動詞
    3: X | 意味が違う
    4: たぶん正解
    """
    let grades = Prompts.parseWordTestReview(raw)
    #expect(grades[1] == WordGrade(verdict: .known, comment: "同じ意味"))
    #expect(grades[2]?.verdict == .unsure)
    #expect(grades[3]?.verdict == .notYet)
    #expect(grades[4] == nil)
}

@Test func writingTaskAndGradeAreParsed() throws {
    let task = try #require(Prompts.parseWritingTask("SCENE: Slack\nTASK: レビューのお礼を伝える"))
    #expect(task == WritingTask(scene: "Slack", task: "レビューのお礼を伝える"))
    let raw = """
    SCORE: 72点
    CORRECTED: Thanks for the review!
    良かった点: 短い
    CHUNK: thanks for | 〜をありがとう
    """
    let grade = try #require(Prompts.parseWritingGrade(raw))
    #expect(grade.score == 72)
    #expect(grade.corrected == "Thanks for the review!")
    #expect(grade.feedback == "良かった点: 短い")
    #expect(grade.chunks.map(\.expression) == ["thanks for"])
    #expect(Prompts.parseWritingGrade("いい感じです") == nil)
}

@Test func dayReportCountsOnlyThatDay() {
    let calendar = Calendar(identifier: .gregorian)
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
    let events = [
        ActivityEvent(kind: .wordQuiz, title: "単語テスト", score: 7, total: 10, date: day),
        ActivityEvent(kind: .wordQuiz, title: "単語テスト", score: 3, total: 5, date: day),
        ActivityEvent(kind: .writing, title: "お題", score: 80, date: day),
        ActivityEvent(kind: .writing, title: "お題", score: 61, date: day),
        ActivityEvent(kind: .translated, title: "昨日", date: yesterday),
    ]
    let report = DayReport(events: events, on: day, calendar: calendar)
    #expect(report.events.count == 4)
    #expect(report.quizCorrect == 10 && report.quizTotal == 15)
    #expect(report.writingAverage == 71)
    #expect(report.count(.translated) == 0)
}

@Test func streakCountsBackFromTodayOrYesterday() {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_800_000_000)
    let day = { (offset: Int) in calendar.date(byAdding: .day, value: -offset, to: today)! }
    let events = [day(1), day(2), day(4)].map { ActivityEvent(kind: .cardFlipped, title: "x", date: $0) }
    #expect(events.streak(until: today, calendar: calendar) == 2)
    let withToday = events + [ActivityEvent(kind: .cardFlipped, title: "x", date: today)]
    #expect(withToday.streak(until: today, calendar: calendar) == 3)
    #expect([ActivityEvent]().streak(until: today, calendar: calendar) == 0)
}

@Test func progressSeriesBuildDailyPoints() {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_800_000_000)
    let day = { (offset: Int) in calendar.date(byAdding: .day, value: -offset, to: today)! }
    var old = WordEntry(term: "a", note: "", context: "")
    old.date = day(5)
    var recent = WordEntry(term: "b", note: "", context: "")
    recent.date = day(1)
    let size = ProgressSeries.bookSize([recent, old], days: 3, until: today, calendar: calendar).map(\.value)
    #expect(size == [1, 2, 2])

    let events = [
        ActivityEvent(kind: .wordQuiz, title: "t", score: 3, total: 4, date: day(1)),
        ActivityEvent(kind: .wordQuiz, title: "t", score: 5, total: 6, date: day(1)),
        ActivityEvent(kind: .cardFlipped, title: "x", date: day(1)),
        ActivityEvent(kind: .cardFlipped, title: "x", date: day(3)),
    ]
    #expect(ProgressSeries.quizAccuracy(events, days: 3, until: today, calendar: calendar).map(\.value) == [80])
    #expect(ProgressSeries.activity(events, days: 2, until: today, calendar: calendar).map(\.count) == [1, 2])
    #expect(ProgressSeries.longestStreak(events + [ActivityEvent(kind: .translated, title: "x", date: day(2))], calendar: calendar) == 3)
    #expect(ProgressSeries.studyDays(events, calendar: calendar) == 2)
}

@Test func meaningTestAcceptsAnyListedJapaneseVariant() {
    var entry = WordEntry(term: "let me know", note: "", context: "")
    entry.english = "let me know"
    entry.japanese = "知らせてね・教えて"
    #expect(WordQuiz.isCorrect("教えて", for: entry, direction: .toJapanese))
    #expect(WordQuiz.isCorrect(" 知らせてね。", for: entry, direction: .toJapanese))
    #expect(!WordQuiz.isCorrect("知らせて", for: entry, direction: .toJapanese))
    #expect(WordDirection.toJapanese.prompt(for: entry) == "let me know")
    #expect(WordDirection.toJapanese.expected(for: entry) == "知らせてね・教えて")
}

@Test func wordTestsOfBothDirectionsCountTowardAccuracy() {
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let events = [
        ActivityEvent(kind: .wordQuiz, title: "t", score: 8, total: 10, date: day),
        ActivityEvent(kind: .meaningQuiz, title: "t", score: 2, total: 10, date: day),
        ActivityEvent(kind: .reading, title: "t", score: 90, date: day),
    ]
    let report = DayReport(events: events, on: day, calendar: Calendar(identifier: .gregorian))
    #expect(report.quizCorrect == 10 && report.quizTotal == 20)
    #expect(report.readingAverage == 90 && report.writingAverage == nil)
}
