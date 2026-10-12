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

@Test func activityMergeAddsOnlyUnknownEventsInDateOrder() {
    let early = ActivityEvent(kind: .cardFlipped, title: "a", date: Date(timeIntervalSince1970: 100))
    let late = ActivityEvent(kind: .translated, title: "b", date: Date(timeIntervalSince1970: 300))
    let middle = ActivityEvent(kind: .wordSaved, title: "c", date: Date(timeIntervalSince1970: 200))
    let merged = ActivitySync.merge([early, late], with: [ActivityRow(middle), ActivityRow(early)])
    #expect(merged.map(\.title) == ["a", "c", "b"])
}

@Test func activityLedgerSendsPendingOnce() {
    let event = ActivityEvent(kind: .writing, title: "t", score: 80, answer: "Thanks!")
    var ledger = ActivityLedger.initial(for: [event])
    let rows = ledger.rows(from: [event])
    #expect(rows.count == 1 && rows[0].kind == "writing" && rows[0].data.answer == "Thanks!")
    ledger.didPush(rows)
    #expect(ledger.rows(from: [event]).isEmpty)
}

@Test func oldActivityEventsStillDecode() throws {
    let json = #"[{"id":"3BAF57C6-1691-40CE-8F42-01BF58DBEC98","date":"2026-10-09T15:29:42Z","kind":"wordQuiz","title":"Word Test","score":7,"total":10}]"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let events = try decoder.decode([ActivityEvent].self, from: Data(json.utf8))
    #expect(events.first?.answers == nil && events.first?.score == 7)
}

@Test func wordKeyIgnoresCaseSpacingAndPunctuation() {
    #expect(WordEntry.key(for: "  Let  me Know. ") == "let me know")
    #expect(WordEntry.key(for: "don’t worry") == WordEntry.key(for: "Don't worry!"))
    #expect(WordEntry.key(for: "LGTM") != WordEntry.key(for: "LGTM it"))
}

@Test func duplicateWordsMergeIntoTheOldestWithCombinedRecords() {
    var old = WordEntry(term: "stop by", note: "立ち寄る", context: "")
    old.date = Date(timeIntervalSince1970: 100)
    old.flips = 2
    old.mastery = .unsure
    old.lastReviewed = Date(timeIntervalSince1970: 200)
    var dup = WordEntry(term: "Stop by.", note: "", context: "Feel free to stop by.")
    dup.date = Date(timeIntervalSince1970: 150)
    dup.flips = 3
    dup.mastery = .known
    dup.lastReviewed = Date(timeIntervalSince1970: 300)
    let other = WordEntry(term: "grab a drink", note: "", context: "")
    let result = WordDedupe.merge([dup, other, old])
    #expect(result.words.count == 2)
    let merged = try! #require(result.words.first { $0.id == old.id })
    #expect(merged.flips == 5 && merged.mastery == .known && merged.note == "立ち寄る" && merged.context == "Feel free to stop by.")
    #expect(result.removedIDs == [dup.id] && result.changedIDs == [old.id])
}

@Test func mixedTranslationKeepsOnlyKnownTermsInEnglish() {
    let raw = "⟦FYI | ご参考までに⟧、⟦hotfix | 緊急修正⟧を出しました。⟦rollback | 切り戻し⟧の計画を見て⟦ASA"
    let mixed = MixedTranslation.parse(raw, knownTerms: ["FYI", "Hotfix"])
    // rollback は残す語に入っていないので日本語に戻す。書きかけの「⟦ASA」は出さない
    #expect(mixed.text == "FYI、hotfix を出しました。切り戻しの計画を見て")
    #expect(mixed.japanese == "ご参考までに、緊急修正を出しました。切り戻しの計画を見て")
    #expect(mixed.keptTerms == ["FYI", "Hotfix"])
    #expect((mixed.text as NSString).substring(with: mixed.kept[1].range) == "hotfix")
    #expect(mixed.englishCharacters == 9)
    #expect(mixed.points(excluding: []) == 20)
    #expect(mixed.points(excluding: ["fyi"]) == 10)
    #expect(MixedTranslation.parse("金曜は⟦OOO | 休暇⟧です", knownTerms: ["OOO"]).text == "金曜は OOO です")
    // Book に無い語は、AI が足したやさしい語として残し、5点にする
    let tried = MixedTranslation.parse("⟦useful | 便利な⟧なスキルです。⟦pstack | 道具⟧", knownTerms: [], triedTerms: ["useful"])
    #expect(tried.text == "useful なスキルです。道具")
    #expect(tried.triedTerms == ["useful"])
    #expect(MixedTranslation.parse("⟦missing | 欠けた⟧⟦records | 記録⟧", knownTerms: [], triedTerms: ["missing", "records"]).text == "missing records")
    #expect(tried.points(excluding: []) == 5)
    // 英文に無い語は残さない
    #expect(MixedTranslation.parse("⟦Hi | こんにちは⟧、ありがとう", knownTerms: ["Hi"], source: "Thanks for this").text == "こんにちは、ありがとう")
}

@Test func easyWordsMustBeInTheSourceAndNotBeingLearned() {
    let words = MixedTranslation.parseEasyWords("- useful\nengineer\nmeeting\nstyle\nUseful", source: "a useful tool by an engineer with style", excluding: ["Style"])
    #expect(words == ["useful", "engineer"])
}

@Test func englishDetectionIgnoresJapanese() {
    #expect(MixedTranslation.isEnglish("Could you take a look at this PR?"))
    #expect(!MixedTranslation.isEnglish("この PR を見てもらえますか?"))
    #expect(!MixedTranslation.isEnglish("OK"))
}

@Test func pointsUseRecordedPointsOrTenPerCorrectAnswer() {
    let events = [
        ActivityEvent(kind: .glossRead, title: "a", score: 9, total: 40, points: 30),
        ActivityEvent(kind: .wordQuiz, title: "b", score: 7, total: 10),
        ActivityEvent(kind: .translated, title: "c"),
    ]
    #expect(Points.total(events) == 100)
}

@Test func wordsSortAlphabeticallyByEnglishAndShuffleRandomly() {
    let words = ["deploy", "ASAP", "backfill"].map { WordEntry(term: $0, note: "", context: "") }
    #expect(words.sorted(by: .alphabetical).map(\.term) == ["ASAP", "backfill", "deploy"])
    #expect(Set(words.sorted(by: .random).map(\.term)) == Set(["deploy", "ASAP", "backfill"]))
}

@Test func lessonBriefGroupsWordsByMasteryAndListsMistakes() {
    var known = WordEntry(term: "FYI", note: "", context: "")
    known.japanese = "参考までに"
    known.mastery = .known
    var learning = WordEntry(term: "hotfix", note: "緊急の修正\n詳しい説明", context: "")
    learning.mastery = .unsure
    let quiz = ActivityEvent(
        kind: .wordQuiz, title: "Word Test", score: 0, total: 1,
        answers: [WordAnswer(wordID: learning.id, prompt: "緊急の修正", answer: "", verdict: .notYet)]
    )
    let markdown = LessonBrief(words: [known, learning], events: [quiz]).markdown()
    #expect(markdown.contains("## Words: Known (1)\n\n- FYI — 参考までに"))
    #expect(markdown.contains("## Words: Unsure (1)\n\n- hotfix — 緊急の修正\n"))
    #expect(markdown.contains("- 緊急の修正 → my answer: (blank) (correct: hotfix — 緊急の修正)"))
    #expect(markdown.contains("Word Test, last 30 days: 0 / 1 correct"))
}

@Test func choiceOptionsHoldTheAnswerAndDistinctDistractors() {
    func card(_ english: String, _ japanese: String) -> WordEntry {
        var word = WordEntry(term: english, note: "", context: "")
        word.english = english
        word.japanese = japanese
        return word
    }
    let target = card("hotfix", "緊急の修正")
    let words = [target, card("deploy", "デプロイする"), card("Deploy", "展開する"), card("FYI", "参考までに"), card("edge case", "境界のケース")]
    let options = ChoiceQuiz.options(for: target, among: words, direction: .toEnglish)
    #expect(options.count == 4)
    #expect(options.contains(ChoiceOption(text: "hotfix", meaning: "緊急の修正")))
    #expect(Set(options.map { $0.text.lowercased() }).count == 4)
}

@Test func choiceMasteryStepsUpOneLevelAndResetsOnMiss() {
    #expect(ChoiceQuiz.nextMastery(after: .notYet, correct: true) == .unsure)
    #expect(ChoiceQuiz.nextMastery(after: .unsure, correct: true) == .known)
    #expect(ChoiceQuiz.nextMastery(after: .known, correct: true) == .known)
    #expect(ChoiceQuiz.nextMastery(after: .known, correct: false) == .notYet)
}

@Test func growthCountsFirstCorrectSeparatelyForChoiceTests() {
    let word = UUID(), other = UUID()
    let day = Date(timeIntervalSince1970: 1_791_700_000)
    let typed = ActivityEvent(kind: .wordQuiz, title: "Word Test", answers: [
        WordAnswer(wordID: word, prompt: "", answer: "", verdict: .known),
        WordAnswer(wordID: other, prompt: "", answer: "", verdict: .notYet),
    ], date: day)
    let again = ActivityEvent(kind: .meaningQuiz, title: "Meaning Test", answers: [WordAnswer(wordID: word, prompt: "", answer: "", verdict: .known)], date: day.addingTimeInterval(86_400))
    let choice = ActivityEvent(kind: .wordQuiz, title: ChoiceQuiz.title, answers: [WordAnswer(wordID: other, prompt: "", answer: "", verdict: .known)], date: day)
    let said = Growth.firstCorrect([again, typed, choice], choice: false)
    #expect(said == [word: day])
    #expect(Growth.firstCorrect([typed, choice], choice: true) == [other: day])
    #expect(Growth.newlyCorrect(said, on: day) == [word])
    #expect(Growth.cumulative(said, days: 3, until: day.addingTimeInterval(86_400)).map(\.value) == [0, 1, 1])
}

@Test func writingAverageUsesTheLastFiveScores() {
    #expect(Growth.movingAverage([40, 60, 80, 100, 20, 100]) == [40, 50, 60, 70, 60, 72])
}

@Test func englishPartsSkipJapanese() {
    #expect(MixedTranslation.englishParts(of: "rule of thumb 経験則・大まかな目安") == "rule of thumb")
    #expect(MixedTranslation.englishParts(of: "FYI、ログインの hotfix をプッシュしました。") == "FYI. hotfix")
    #expect(MixedTranslation.englishParts(of: "I'll push back on it.") == "I'll push back on it")
    #expect(MixedTranslation.englishParts(of: "日本語だけ") == nil)
}

@Test func questionWeightsFavorUnlearnedAndStaleWords() {
    let now = Date(timeIntervalSince1970: 1_791_800_000)
    func card(_ mastery: Mastery, daysAgo: Double?) -> WordEntry {
        var word = WordEntry(term: "w", note: "", context: "")
        word.english = "w"
        word.japanese = "ダブリュー"
        word.mastery = mastery
        word.lastReviewed = daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        return word
    }
    #expect(WordQuiz.weight(of: card(.notYet, daysAgo: 0), now: now) == 6)
    #expect(WordQuiz.weight(of: card(.known, daysAgo: 7), now: now) == 2)
    let words = (0..<20).map { _ in card(.known, daysAgo: 0) } + (0..<20).map { _ in card(.notYet, daysAgo: 0) }
    let known = (0..<200).map { _ in WordQuiz.pick(from: words, now: now).filter { $0.masteryLevel == .known }.count }.reduce(0, +)
    #expect(known > 0 && known < 1_000)
}

@Test func recommendedSortPutsLikelyForgottenWordsFirst() {
    let now = Date(timeIntervalSince1970: 1_791_800_000)
    func card(_ term: String, _ mastery: Mastery, daysAgo: Double) -> WordEntry {
        var word = WordEntry(term: term, note: "", context: "")
        word.mastery = mastery
        word.lastReviewed = now.addingTimeInterval(-daysAgo * 86_400)
        return word
    }
    let fresh = card("fresh", .notYet, daysAgo: 0)
    let stale = card("stale", .notYet, daysAgo: 3)
    let known = card("known", .known, daysAgo: 3)
    var proven = card("proven", .unsure, daysAgo: 3)
    proven.lastReviewed = now.addingTimeInterval(-3 * 86_400)
    let test = ActivityEvent(kind: .wordQuiz, title: "Word Test", answers: [
        WordAnswer(wordID: proven.id, prompt: "", answer: "", verdict: .known),
    ], date: now.addingTimeInterval(-3 * 86_400))
    #expect([fresh, known, proven, stale].sorted(by: .recommended, events: [test], now: now).map(\.term) == ["stale", "proven", "known", "fresh"])
    #expect(Recall.streaks([test]) == [proven.id: 1])
}

@Test func bookSearchMatchesEnglishJapaneseAndNotes() {
    var word = WordEntry(term: "Rule of Thumb", note: "大まかな目安", context: "")
    word.japanese = "経験則"
    #expect(word.matches("rule of"))
    #expect(word.matches("経験"))
    #expect(word.matches("目安"))
    #expect(word.matches("  "))
    #expect(!word.matches("deploy"))
}

@Test func gradedTranslationRendersEachLevelFromOneAnswer() {
    let source = "FYI, I pushed a hotfix for the login timeout. Let's check the edge case before we deploy to production."
    let raw = "⟦FYI | 参考までに | 2⟧、⟦login timeout | ログインのタイムアウト | 3⟧に対する⟦hotfix | 緊急修正 | 4⟧をプッシュしました。⟦deploy to production | 本番に出す | 3⟧前に、⟦edge case | 想定外のケース | 4⟧を⟦check | 確認する | 1⟧しましょう。"
    let graded = GradedTranslation.parse(raw, knownTerms: ["hotfix"], source: source)
    #expect(graded.phrases.count == 6)
    #expect(graded.japanese == "参考までに、ログインのタイムアウトに対する緊急修正をプッシュしました。本番に出す前に、想定外のケースを確認するしましょう。")
    #expect(graded.rendered(.japanese).englishRate == 0)
    let rates = [EnglishLevel.ten, .thirty, .fifty].map { graded.rendered($0).englishRate }
    #expect(rates == rates.sorted())
    #expect(graded.rendered(.ten).learnedTerms == ["hotfix"])
    let ninety = graded.rendered(.ninety)
    #expect(ninety.text.hasPrefix("FYI, I pushed a hotfix"))
    #expect(ninety.englishRate >= 70)
}
