import { millis } from "./ids";
import { activityLabel, Mastery, masteryLabel, type ActivityEvent, type WordEntry } from "./models";
import { quizTotals, streak, totalPoints } from "./report";

// ChatGPT などの音声通話に貼って、英語のレッスンをしてもらうための学習状況のまとめ。
// Mac の LessonBrief と同じ文を作る。単語帳は全部、テストの記録は最近の分だけ入れる
export const RECENT_DAYS = 30;
export const MISSED_LIMIT = 40;
export const WRITING_LIMIT = 10;

const pad = (n: number) => String(n).padStart(2, "0");
const dateText = (date: Date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const masteryOf = (word: WordEntry) => word.mastery ?? Mastery.NotYet;
// 新しい順。同期では秒より細かい時刻が落ちるので秒で比べ、同じ秒なら id で決めて Mac と並びを揃える
const seconds = (iso: string) => Math.floor(millis(iso) / 1000);
const newestFirst = <T extends { id: string; date: string }>(a: T, b: T) =>
  seconds(b.date) - seconds(a.date) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export function lessonBrief(words: WordEntry[], events: ActivityEvent[], now = new Date()): string {
  const since = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1 - RECENT_DAYS).getTime();
  const recent = events.filter((event) => millis(event.date) >= since);
  const count = (mastery: Mastery) => words.filter((word) => masteryOf(word) === mastery).length;
  const studyDays = new Set(events.map((event) => dateText(new Date(event.date)))).size;
  const lines = [
    "# My English Learning Data (Gloss)",
    "",
    "You are my English tutor in a voice lesson.",
    "Use the data below to run the lesson.",
    "",
    "## Summary",
    "",
    `- Date: ${dateText(now)}`,
    `- Study streak: ${streak(events, now)} days (study days in total: ${studyDays})`,
    `- Points: ${totalPoints(events)}`,
    `- Words in my Book: ${words.length} (Known ${count(Mastery.Known)}, Unsure ${count(Mastery.Unsure)}, Not Yet ${count(Mastery.NotYet)})`,
  ];
  const quiz = quizTotals(recent);
  if (quiz.total > 0) lines.push(`- Word Test, last ${RECENT_DAYS} days: ${quiz.correct} / ${quiz.total} correct`);
  const reads = recent.filter((event) => event.kind === "glossRead");
  const readTotal = reads.reduce((sum, event) => sum + (event.total ?? 0), 0);
  if (readTotal > 0) {
    const english = reads.reduce((sum, event) => sum + (event.score ?? 0), 0);
    lines.push(`- English left in my translations, last ${RECENT_DAYS} days: ${Math.floor((english * 100) / readTotal)}%`);
  }

  for (const mastery of [Mastery.NotYet, Mastery.Unsure, Mastery.Known]) {
    const entries = words.filter((word) => masteryOf(word) === mastery).sort(newestFirst);
    if (!entries.length) continue;
    lines.push("", `## Words: ${masteryLabel[mastery]} (${entries.length})`, "", ...entries.map(wordLine));
  }

  const missed = recent
    .filter((event) => event.kind === "wordQuiz" || event.kind === "meaningQuiz")
    .sort(newestFirst)
    .flatMap((event) => event.answers ?? [])
    .filter((answer) => answer.verdict !== Mastery.Known)
    .slice(0, MISSED_LIMIT);
  if (missed.length) {
    lines.push("", "## Recent Word Test Mistakes", "");
    const byID = new Map(words.map((word) => [word.id, word]));
    lines.push(
      ...missed.map((answer) => {
        const word = byID.get(answer.wordID);
        const line = `- ${flat(answer.prompt)} → my answer: ${answer.answer ? flat(answer.answer) : "(blank)"}`;
        return word ? `${line} (correct: ${pair(word)})` : line;
      }),
    );
  }

  const writings = recent
    .filter((event) => event.kind === "writing" || event.kind === "reading")
    .sort(newestFirst)
    .slice(0, WRITING_LIMIT);
  if (writings.length) {
    lines.push("", "## Recent Writing / Reading Tests", "");
    for (const event of writings) {
      lines.push(`- ${activityLabel[event.kind]}: ${flat(event.title)} (${event.score ?? 0} pts)`);
      if (event.answer) lines.push(`  - My answer: ${flat(event.answer)}`);
      if (event.detail) lines.push(`  - Corrected: ${flat(event.detail)}`);
    }
  }
  return lines.join("\n");
}

// 「英語 — 日本語 (例文)」の1行にする
export function wordLine(word: WordEntry): string {
  const line = `- ${pair(word)}`;
  return word.example ? `${line} (e.g. ${flat(word.example)})` : line;
}

// カードの訳がまだ無い単語は、保存したときの説明の空でない1行目を、80文字まで使う。
// Mac と同じ数え方にするため、文字は Unicode のコードポイントで数える
export function pair(word: WordEntry): string {
  const rawEnglish = word.english ?? word.term;
  const english = flat(rawEnglish);
  const firstLine = word.note.split("\n").find((line) => line.trim() !== "") ?? "";
  const note = Array.from(firstLine).slice(0, 80).join("");
  const meaning = flat(word.japanese ?? (word.term === rawEnglish ? note : word.term));
  return meaning ? `${english} — ${meaning}` : english;
}

// 複数行の答えや添削で箇条書きが崩れないよう、改行を「 / 」にして1行にする
export function flat(text: string): string {
  return text
    .split(/\r\n|\r|\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "")
    .join(" / ");
}
