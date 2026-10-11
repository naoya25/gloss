import { describe, expect, it } from "vitest";
import { isoSeconds, newID } from "./ids";
import { Mastery, type ActivityEvent, type WordEntry } from "./models";
import { lessonBrief } from "./lessonBrief";
import { choiceOptions, isExactAnswer, nextMastery, pickQuestions } from "./quiz";
import { bookSize, lastDays, quizTotals, streak } from "./report";
import { pickVoice } from "./speech";
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
