import { describe, expect, it } from "vitest";
import { cumulative, firstCorrect, movingAverage, newlyCorrect } from "./growth";
import { isoSeconds, newID } from "./ids";
import { Mastery, type ActivityEvent, type WordEntry } from "./models";
import { lessonBrief } from "./lessonBrief";
import { choiceOptions, isExactAnswer, nextMastery, pickQuestions, questionWeight } from "./quiz";
import { bookSize, lastDays, quizTotals, streak } from "./report";
import { pickVoice } from "./speech";
import { japaneseOf, joinGraded, levelAbove, parseGraded, phrasesOf, readAbility, readingPoints, render, splitParts } from "./graded";
import { matchesQuery, recallStreaks } from "./recall";
import { sortWords } from "../pages/book/store";
import { activityRow, didPushWords, mergeActivity, mergeWords, wordRows } from "./sync";

const word = (patch: Partial<WordEntry> = {}): WordEntry => ({
  id: newID(),
  date: "2026-10-01T00:00:00Z",
  term: "let me know",
  note: "",
  context: "",
  english: "let me know",
  japanese: "知らせてね・教えて",
  ...patch,
});

describe("ids", () => {
  it("dates drop milliseconds so Swift can read them", () => {
    expect(isoSeconds(new Date(Date.UTC(2026, 9, 10, 1, 2, 3, 456)))).toBe("2026-10-10T01:02:03Z");
  });
  it("ids are uppercase like Swift uuidString", () => {
    expect(newID()).toMatch(/^[0-9A-F-]{36}$/);
  });
});

describe("mergeWords", () => {
  it("takes newer remote words and ignores older ones", () => {
    const local = word({ updatedAt: isoSeconds(new Date(2000)), note: "old" });
    const newer = mergeWords([local], [{ id: local.id, updatedAt: 5000, deleted: false, data: { ...local, note: "new" } }], { cursor: 0, pending: {} });
    expect(newer[0]!.note).toBe("new");
    const kept = mergeWords([local], [{ id: local.id, updatedAt: 1000, deleted: false, data: { ...local, note: "older" } }], { cursor: 0, pending: {} });
    expect(kept[0]!.note).toBe("old");
  });
  it("keeps an unsent local change that is newer than the remote one", () => {
    const local = word();
    const merged = mergeWords([local], [{ id: local.id, updatedAt: 1000, deleted: true, data: null }], { cursor: 0, pending: { [local.id]: 9000 } });
    expect(merged).toHaveLength(1);
  });
  it("keeps fields the web app does not know about", () => {
    const local = word({ engine: "jai", cardError: "x" });
    const rows = wordRows([local], { cursor: 0, pending: { [local.id]: 1 } });
    expect(rows[0]!.data!.engine).toBe("jai");
  });
  it("leaves words that changed while sending in pending", () => {
    const ledger = { cursor: 0, pending: { A: 1, B: 2 } };
    const sent = wordRows([], ledger);
    const after = didPushWords({ cursor: 0, pending: { A: 1, B: 3 } }, sent);
    expect(after.pending).toEqual({ B: 3 });
  });
});

describe("mergeActivity", () => {
  it("adds only unknown events in date order", () => {
    const a: ActivityEvent = { id: "A", date: "2026-10-01T00:00:00Z", kind: "cardFlipped", title: "a" };
    const b: ActivityEvent = { id: "B", date: "2026-10-02T00:00:00Z", kind: "cardFlipped", title: "b" };
    const c: ActivityEvent = { id: "C", date: "2026-10-03T00:00:00Z", kind: "cardFlipped", title: "c" };
    expect(mergeActivity([a, c], [activityRow(b), activityRow(a)]).map((event) => event.title)).toEqual(["a", "b", "c"]);
  });
});

describe("isExactAnswer", () => {
  it("ignores case, spacing, and punctuation in English", () => {
    expect(isExactAnswer("  Let  me KNOW. ", word(), "toEnglish")).toBe(true);
    expect(isExactAnswer("let me", word(), "toEnglish")).toBe(false);
  });
  it("accepts any listed Japanese variant", () => {
    expect(isExactAnswer("教えて", word(), "toJapanese")).toBe(true);
    expect(isExactAnswer("知らせて", word(), "toJapanese")).toBe(false);
  });
});

describe("report", () => {
  const today = new Date(2026, 9, 10, 12);
  const at = (days: number) => new Date(2026, 9, 10 - days, 9).toISOString();
  it("counts the streak from today or yesterday", () => {
    const events = [1, 2, 4].map((d): ActivityEvent => ({ id: `${d}`, date: at(d), kind: "cardFlipped", title: "" }));
    expect(streak(events, today)).toBe(2);
    expect(streak([...events, { id: "t", date: at(0), kind: "translated", title: "" }], today)).toBe(3);
  });
  it("adds word test totals of both directions", () => {
    const events: ActivityEvent[] = [
      { id: "1", date: at(0), kind: "wordQuiz", title: "", score: 7, total: 10 },
      { id: "2", date: at(0), kind: "meaningQuiz", title: "", score: 3, total: 10, answers: [{ wordID: "W", prompt: "p", answer: "a", verdict: Mastery.Known }] },
    ];
    expect(quizTotals(events)).toEqual({ correct: 10, total: 20 });
  });
  it("stacks the book size by the day words were added", () => {
    const words = [word({ date: at(5) }), word({ date: at(1) })];
    expect(bookSize(words, lastDays(3, today))).toEqual([1, 2, 2]);
  });
});

describe("pickQuestions", () => {
  it("avoids the words from the last test when there are enough others", () => {
    const words = Array.from({ length: 25 }, (_, i) => word({ term: `w${i}` }));
    const first = pickQuestions(words);
    const next = pickQuestions(words, 10, new Set(first.map((w) => w.id)));
    expect(next).toHaveLength(10);
    expect(next.some((w) => first.includes(w))).toBe(false);
  });
  it("weights not-yet and long-unseen words higher, but known words can still appear", () => {
    const now = Date.UTC(2026, 9, 12);
    const day = (ago: number) => new Date(now - ago * 86_400_000).toISOString();
    expect(questionWeight(word({ mastery: Mastery.NotYet, lastReviewed: day(0) }), now)).toBe(6);
    expect(questionWeight(word({ mastery: Mastery.Known, lastReviewed: day(7) }), now)).toBe(2);
    expect(questionWeight(word({ mastery: Mastery.Unsure }), now)).toBeCloseTo(3 * (1 + 30 / 7));
    const known = Array.from({ length: 20 }, (_, i) => word({ term: `k${i}`, mastery: Mastery.Known, lastReviewed: day(0) }));
    const notYet = Array.from({ length: 20 }, (_, i) => word({ term: `n${i}`, mastery: Mastery.NotYet, lastReviewed: day(0) }));
    let knownPicked = 0;
    for (let i = 0; i < 200; i++) knownPicked += pickQuestions([...known, ...notYet], 10, new Set(), now).filter((w) => w.mastery === Mastery.Known).length;
    expect(knownPicked).toBeGreaterThan(0);
    expect(knownPicked).toBeLessThan(200 * 5);
  });
  it("reuses recent words only when there are not enough others", () => {
    const words = Array.from({ length: 12 }, (_, i) => word({ term: `w${i}` }));
    const recent = new Set(words.slice(0, 10).map((w) => w.id));
    expect(pickQuestions(words, 10, recent)).toHaveLength(10);
  });
});

describe("pickVoice", () => {
  const voice = (name: string, lang: string) => ({ name, lang }) as SpeechSynthesisVoice;

  it("prefers Samantha, then American English, then any English", () => {
    expect(pickVoice([voice("Daniel", "en-GB"), voice("Samantha", "en-US"), voice("Alex", "en-US")])?.name).toBe("Samantha");
    expect(pickVoice([voice("Daniel", "en-GB"), voice("Alex", "en-US")])?.name).toBe("Alex");
    expect(pickVoice([voice("Kyoko", "ja-JP"), voice("Daniel", "en-GB")])?.name).toBe("Daniel");
    expect(pickVoice([voice("Samantha", "en-US"), voice("Samantha (Enhanced)", "en-US")])?.name).toBe("Samantha (Enhanced)");
  });
});

describe("lessonBrief", () => {
  it("groups words by mastery and lists recent mistakes like the Mac", () => {
    const known = word({ term: "FYI", english: undefined, japanese: "参考までに", mastery: Mastery.Known });
    const learning = word({ term: "hotfix", english: undefined, japanese: undefined, note: "緊急の修正\n詳しい説明", mastery: Mastery.Unsure });
    const now = new Date(2026, 9, 11, 12);
    const quiz: ActivityEvent = {
      id: "q",
      date: new Date(2026, 9, 10).toISOString(),
      kind: "wordQuiz",
      title: "Word Test",
      score: 0,
      total: 1,
      answers: [{ wordID: learning.id, prompt: "緊急の修正", answer: "", verdict: Mastery.NotYet }],
    };
    const text = lessonBrief([known, learning], [quiz], now);
    expect(text).toContain("- Date: 2026-10-11");
    expect(text).toContain("## Words: Known (1)\n\n- FYI — 参考までに");
    expect(text).toContain("## Words: Unsure (1)\n\n- hotfix — 緊急の修正\n");
    expect(text).toContain("- 緊急の修正 → my answer: (blank) (correct: hotfix — 緊急の修正)");
    expect(text).toContain("Word Test, last 30 days: 0 / 1 correct");
  });
});

describe("4-choice test", () => {
  it("options hold the answer and distinct distractors", () => {
    const target = word({ english: "hotfix", term: "hotfix", japanese: "緊急の修正" });
    const words = [target, word({ english: "deploy" }), word({ english: "Deploy" }), word({ english: "FYI" }), word({ english: "edge case" })];
    for (let i = 0; i < 50; i++) {
      const options = choiceOptions(target, words, "toEnglish");
      expect(options).toHaveLength(4);
      expect(options).toContainEqual({ text: "hotfix", meaning: "緊急の修正" });
      expect(new Set(options.map((option) => option.text.toLowerCase())).size).toBe(4);
    }
  });
  it("steps mastery up one level and resets on a miss", () => {
    expect(nextMastery(Mastery.NotYet, true)).toBe(Mastery.Unsure);
    expect(nextMastery(Mastery.Unsure, true)).toBe(Mastery.Known);
    expect(nextMastery(Mastery.Known, true)).toBe(Mastery.Known);
    expect(nextMastery(Mastery.Known, false)).toBe(Mastery.NotYet);
  });
});

describe("growth", () => {
  it("counts first correct answers, keeping 4-choice apart", () => {
    const at = (day: number) => new Date(2026, 9, day, 12).toISOString();
    const typed: ActivityEvent = { id: "1", date: at(10), kind: "wordQuiz", title: "Word Test", answers: [
      { wordID: "a", prompt: "", answer: "", verdict: Mastery.Known },
      { wordID: "b", prompt: "", answer: "", verdict: Mastery.NotYet },
    ] };
    const again: ActivityEvent = { id: "2", date: at(11), kind: "meaningQuiz", title: "Meaning Test", answers: [{ wordID: "a", prompt: "", answer: "", verdict: Mastery.Known }] };
    const choice: ActivityEvent = { id: "3", date: at(10), kind: "wordQuiz", title: "4-Choice Test", answers: [{ wordID: "b", prompt: "", answer: "", verdict: Mastery.Known }] };
    const said = firstCorrect([again, typed, choice], false);
    expect([...said.keys()]).toEqual(["a"]);
    expect([...firstCorrect([typed, choice], true).keys()]).toEqual(["b"]);
    expect(newlyCorrect(said, new Date(2026, 9, 10))).toEqual(["a"]);
    expect(cumulative(said, [new Date(2026, 9, 9), new Date(2026, 9, 10), new Date(2026, 9, 11)])).toEqual([0, 1, 1]);
  });
  it("averages the last five writing scores", () => {
    expect(movingAverage([40, 60, 80, 100, 20, 100])).toEqual([40, 50, 60, 70, 60, 72]);
  });
});

describe("recommended order and search", () => {
  it("puts likely forgotten words first, using test streaks", () => {
    const now = Date.UTC(2026, 9, 12);
    const ago = (days: number) => new Date(now - days * 86_400_000).toISOString();
    const fresh = word({ term: "fresh", mastery: Mastery.NotYet, lastReviewed: ago(0) });
    const stale = word({ term: "stale", mastery: Mastery.NotYet, lastReviewed: ago(3) });
    const known = word({ term: "known", mastery: Mastery.Known, lastReviewed: ago(3) });
    const proven = word({ term: "proven", mastery: Mastery.Unsure, lastReviewed: ago(3) });
    const test: ActivityEvent = { id: "t", date: ago(3), kind: "wordQuiz", title: "Word Test", answers: [{ wordID: proven.id, prompt: "", answer: "", verdict: Mastery.Known }] };
    const order = sortWords([fresh, known, proven, stale], "recommended", [test], now);
    expect(order).toEqual([stale.id, proven.id, known.id, fresh.id]);
    expect(recallStreaks([test]).get(proven.id)).toBe(1);
  });
  it("searches English, Japanese and notes ignoring case and width", () => {
    const entry = word({ term: "Rule of Thumb", english: "rule of thumb", japanese: "経験則", note: "大まかな目安" });
    expect(matchesQuery(entry, "RULE OF")).toBe(true);
    expect(matchesQuery(entry, "ｒｕｌｅ")).toBe(true);
    expect(matchesQuery(entry, "目安")).toBe(true);
    expect(matchesQuery(entry, "deploy")).toBe(false);
  });
});

describe("graded translation", () => {
  const source = "FYI, I pushed a hotfix for the login timeout. Let's check the edge case before we deploy to production.";
  const raw =
    "⟦FYI | 参考までに | 2⟧、⟦login timeout | ログインのタイムアウト | 3⟧に対する⟦hotfix | 緊急修正 | 4⟧を⟦push | プッシュ | 2⟧しました。⟦production | 本番 | 2⟧に⟦deploy | デプロイ | 3⟧する前に、⟦edge case | 想定外のケース | 4⟧を⟦check | 確認 | 1⟧しましょう。";
  it("renders each level from one answer, like the Mac", () => {
    const graded = parseGraded(raw, ["hotfix"], source);
    expect(phrasesOf(graded)).toHaveLength(8);
    expect(render(graded, 0).text).toBe("参考までに、ログインのタイムアウトに対する緊急修正をプッシュしました。本番にデプロイする前に、想定外のケースを確認しましょう。");
    const ten = render(graded, 10);
    expect(ten.kept.map((k) => k.english)).toContain("hotfix");
    const counts = ([10, 30, 50] as const).map((level) => render(graded, level).kept.length);
    expect(counts).toEqual([...counts].sort((a, b) => a - b));
    expect(counts[0]).toBeLessThan(counts[2]!);
    expect(render(graded, 50).text).toContain("push しました");
    expect(render(graded, 90).text.startsWith("FYI, I pushed a hotfix")).toBe(true);
    expect(readingPoints(render(graded, 0), 0)).toBe(0);
  });
  it("turns tapped phrases into Japanese and lowers the next level, like the Mac", () => {
    const graded = parseGraded(raw, ["hotfix"], source);
    expect(readAbility(graded, 50, new Set())).toBe(50);
    expect(levelAbove(50)).toBe(90);
    const tapped = render(graded, 50, new Set(["hotfix"]));
    expect(tapped.kept.map((k) => k.english)).not.toContain("hotfix");
    expect(tapped.text).toContain("緊急修正");
    expect(readAbility(graded, 50, new Set(["hotfix"]))).toBeLessThan(50);
    const all = new Set(render(graded, 50).clickable.map((k) => k.english.toLowerCase()));
    expect(readAbility(graded, 50, all)).toBe(0);
    const back = tapped.revealed[0]!;
    expect(back.english).toBe("hotfix");
    expect(tapped.text.slice(back.start, back.end)).toBe("緊急修正");
    expect([levelAbove(0), levelAbove(25), levelAbove(90)]).toEqual([10, 30, 90]);
    expect(readAbility(graded, 0, new Set())).toBe(0);
    const ninety = render(graded, 90);
    expect(ninety.clickable.map((k) => k.english)).toContain("check");
    const glossed = render(graded, 90, new Set(["check"]));
    expect(glossed.text.slice(glossed.revealed[0]!.start, glossed.revealed[0]!.end)).toBe("check（確認）");
    expect(readAbility(graded, 90, new Set(["check"]))).toBeLessThan(90);
  });
  it("splits long text into paragraph groups and joins them back", () => {
    const paragraph = "word ".repeat(100);
    const text = [paragraph, paragraph, paragraph].join("\n\n");
    const parts = splitParts(text, 1200);
    expect(parts).toHaveLength(2);
    expect(parts.join("\n\n")).toBe(text);
    const one = parseGraded("⟦word | 語 | 1⟧です", [], "word");
    expect(japaneseOf(joinGraded([one, one], "word\n\nword"))).toBe("語です\n\n語です");
  });
});
