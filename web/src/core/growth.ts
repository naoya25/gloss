import { millis } from "./ids";
import { CHOICE_TITLE } from "./quiz";
import { Mastery, type ActivityEvent } from "./models";

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
