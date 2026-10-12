import { millis } from "./ids";
import { CHOICE_TITLE } from "./quiz";
import { Mastery, type ActivityEvent, type WordEntry } from "./models";

// Report の主役(Mac の Growth と同じ数え方)。やった量ではなく、できるようになったことを数える

const dayKey = (date: Date) => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());
const isWordTest = (event: ActivityEvent) => event.kind === "wordQuiz" || event.kind === "meaningQuiz";

// 語ごとに、テストで初めて正解した時刻。4択は「見て分かった」だけなので、書くテストとは分けて数える
export function firstCorrect(events: ActivityEvent[], choice: boolean): Map<string, number> {
  const firsts = new Map<string, number>();
  const tests = events.filter((event) => isWordTest(event) && (event.title === CHOICE_TITLE) === choice);
  for (const event of tests.sort((a, b) => millis(a.date) - millis(b.date))) {
    for (const answer of event.answers ?? []) {
      if (answer.verdict === Mastery.Known && !firsts.has(answer.wordID)) firsts.set(answer.wordID, millis(event.date));
    }
  }
  return firsts;
}

// その日に初めて正解した語。古い順
export function newlyCorrect(firsts: Map<string, number>, day: Date): string[] {
  const key = dayKey(day);
  return [...firsts].filter(([, at]) => dayKey(new Date(at)) === key).sort((a, b) => a[1] - b[1]).map(([id]) => id);
}

// 初めて正解した語の、日ごとの累計
export function cumulative(firsts: Map<string, number>, days: Date[]): number[] {
  const times = [...firsts.values()];
  return days.map((day) => {
    const end = startOfDay(day).getTime() + 86_400_000;
    return times.filter((at) => at < end).length;
  });
}

// 日ごとの、訳の中で英語のまま読めた割合。訳していない日は null
export function englishRates(events: ActivityEvent[], days: Date[]): (number | null)[] {
  const reads = events.filter((event) => event.kind === "glossRead");
  return days.map((day) => {
    const key = dayKey(day);
    const today = reads.filter((event) => dayKey(new Date(event.date)) === key);
    const total = today.reduce((sum, event) => sum + (event.total ?? 0), 0);
    return total ? (today.reduce((sum, event) => sum + (event.score ?? 0), 0) * 100) / total : null;
  });
}

// 日ごとの記録の数。やった日のカレンダーの濃さに使う
export function dailyCounts(events: ActivityEvent[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const event of events) {
    const key = dayKey(new Date(event.date));
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return counts;
}

export const countOn = (counts: Map<string, number>, day: Date) => counts.get(dayKey(day)) ?? 0;

// Writing Test の点を古い順に。since より前は入れない
export function writingScores(events: ActivityEvent[], since: Date): number[] {
  return events
    .filter((event) => event.kind === "writing" && millis(event.date) >= since.getTime() && event.score !== undefined)
    .sort((a, b) => millis(a.date) - millis(b.date))
    .map((event) => event.score!);
}

// 直近 window 回の平均。最初のうちはあるぶんだけで平均する
export function movingAverage(scores: number[], window = 5): number[] {
  return scores.map((_, i) => {
    const slice = scores.slice(Math.max(0, i - window + 1), i + 1);
    return slice.reduce((a, b) => a + b, 0) / slice.length;
  });
}

const wordKey = (text: string) => text.toLowerCase().replace(/’/g, "'").split(/\s+/).filter(Boolean).join(" ").replace(/^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$/gu, "");

// Book に同じ英語の単語が2つあるときは、1語として数える(早く正解したほうを残す)
export function distinct(firsts: Map<string, number>, words: WordEntry[]): Map<string, number> {
  const keys = new Map(words.map((word) => [word.id, wordKey(word.english || word.term)]));
  const kept = new Map<string, [string, number]>();
  for (const [id, at] of firsts) {
    const key = keys.get(id) ?? id;
    const current = kept.get(key);
    if (!current || at < current[1]) kept.set(key, [id, at]);
  }
  return new Map([...kept.values()]);
}

// いちばん最近、英語のまま読んだ日と、その日の割合。今日まだ読んでいないときに見せる
export function latestEnglish(events: ActivityEvent[]): { day: Date; rate: number } | null {
  const reads = events.filter((event) => event.kind === "glossRead");
  if (!reads.length) return null;
  const last = new Date(Math.max(...reads.map((event) => millis(event.date))));
  const key = dayKey(last);
  const day = reads.filter((event) => dayKey(new Date(event.date)) === key);
  const total = day.reduce((sum, event) => sum + (event.total ?? 0), 0);
  return total ? { day: startOfDay(last), rate: Math.floor((day.reduce((sum, event) => sum + (event.score ?? 0), 0) * 100) / total) } : null;
}

// テストの種類ごとの推移(Mac の TestTrend と同じ)。単語のテストは正答率、文のテストは点で、どちらも 0〜100
export const TEST_TRENDS = [
  { id: "choice", label: "4-Choice Test", unit: "%" },
  { id: "word", label: "Word Test", unit: "%" },
  { id: "meaning", label: "Meaning Test", unit: "%" },
  { id: "writing", label: "Writing Test", unit: "pts" },
  { id: "reading", label: "Reading Test", unit: "pts" },
] as const;
export type TestTrend = (typeof TEST_TRENDS)[number];

export function matchesTest(test: TestTrend, event: ActivityEvent): boolean {
  const choice = event.title === CHOICE_TITLE;
  switch (test.id) {
    case "choice": return isWordTest(event) && choice;
    case "word": return event.kind === "wordQuiz" && !choice;
    case "meaning": return event.kind === "meaningQuiz" && !choice;
    case "writing": return event.kind === "writing";
    case "reading": return event.kind === "reading";
  }
}

// 単語のテストは「何問中何問」を足し合わせた正答率、文のテストは点の平均
export function testValue(test: TestTrend, events: ActivityEvent[]): number | null {
  const mine = events.filter((event) => matchesTest(test, event));
  if (test.unit === "%") {
    const total = mine.reduce((sum, event) => sum + (event.total ?? 0), 0);
    return total ? (mine.reduce((sum, event) => sum + (event.score ?? 0), 0) * 100) / total : null;
  }
  const scores = mine.flatMap((event) => (event.score === undefined ? [] : [event.score]));
  return scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : null;
}

// 日ごとの値。テストをしていない日は null
export function testSeries(test: TestTrend, events: ActivityEvent[], days: Date[]): (number | null)[] {
  return days.map((day) => {
    const key = dayKey(day);
    return testValue(test, events.filter((event) => dayKey(new Date(event.date)) === key));
  });
}

export const formatTest = (test: TestTrend, value: number) => `${Math.round(value)}${test.unit === "%" ? "%" : " pts"}`;

// 日ごとの回数。やっていない日は 0
export function testCounts(test: TestTrend, events: ActivityEvent[], days: Date[]): number[] {
  return days.map((day) => {
    const key = dayKey(day);
    return events.filter((event) => matchesTest(test, event) && dayKey(new Date(event.date)) === key).length;
  });
}

// 始めたばかりで記録が期間より短いときは、始めた日から見せる(最短 7 日)。そうしないとグラフの大半が空になる
export function visibleDays(days: number, events: ActivityEvent[], today = new Date()): number {
  if (!events.length) return days;
  const first = startOfDay(new Date(Math.min(...events.map((event) => millis(event.date)))));
  const span = Math.round((startOfDay(today).getTime() - first.getTime()) / 86_400_000) + 1;
  return Math.min(days, Math.max(7, span));
}
