import { millis } from "./ids";
import { CHOICE_TITLE } from "./quiz";
import { Mastery, type ActivityEvent, type WordEntry } from "./models";

// 忘れていそうな度合いを、忘却曲線(思い出せる見込み = e^(-経過日数 / 記憶の持ち))で見積もる(Mac の Recall と同じ)。
// 記憶の持ちは、印ごとの日数(✕ 0.5・? 2・✓ 7)を、テストで続けて正解した回数だけ倍にしたもの

// 語ごとに、直近から続けて正解した回数。書くテストは 1、4択は見て分かっただけなので 0.5 と数え、外したら途切れる
export function recallStreaks(events: ActivityEvent[]): Map<string, number> {
  const streaks = new Map<string, number>();
  const broken = new Set<string>();
  const tests = events.filter((event) => event.kind === "wordQuiz" || event.kind === "meaningQuiz");
  for (const event of tests.sort((a, b) => millis(b.date) - millis(a.date))) {
    for (const answer of event.answers ?? []) {
      if (broken.has(answer.wordID)) continue;
      if (answer.verdict === Mastery.Known) streaks.set(answer.wordID, (streaks.get(answer.wordID) ?? 0) + (event.title === CHOICE_TITLE ? 0.5 : 1));
      else broken.add(answer.wordID);
    }
  }
  return streaks;
}

// 0(覚えている)〜 1(忘れていそう)。一度も見ていない単語は、追加した日から数える
export function forgetting(word: WordEntry, streak: number, now = Date.now()): number {
  const base = word.mastery === Mastery.Known ? 7 : word.mastery === Mastery.Unsure ? 2 : 0.5;
  const stability = base * 2 ** Math.min(streak, 4);
  const days = Math.max(0, (now - millis(word.lastReviewed ?? word.date)) / 86_400_000);
  return 1 - Math.exp(-days / stability);
}

// Book の検索。英語・日本語・説明・例文のどこかに含まれていれば当たり。大文字小文字と全角半角の違いは無視する
export function matchesQuery(word: WordEntry, query: string): boolean {
  const needle = query.trim().normalize("NFKC").toLowerCase();
  if (!needle) return true;
  return [word.term, word.english, word.japanese, word.note, word.context, word.example, word.exampleTranslation].some(
    (value) => typeof value === "string" && value.normalize("NFKC").toLowerCase().includes(needle),
  );
}
