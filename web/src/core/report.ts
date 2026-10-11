import { millis } from "./ids";
import type { ActivityEvent, ActivityKind, WordEntry } from "./models";

const dayKey = (date: Date) => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());

export function eventsOn(events: ActivityEvent[], day: Date): ActivityEvent[] {
  const key = dayKey(day);
  return events.filter((event) => dayKey(new Date(event.date)) === key).sort((a, b) => millis(b.date) - millis(a.date));
}

export const countKind = (events: ActivityEvent[], kind: ActivityKind) => events.filter((event) => event.kind === kind).length;

// 単語テストは向きに関わらず、正解数と問題数を足し合わせる
export function quizTotals(events: ActivityEvent[]) {
  const tests = events.filter((event) => event.kind === "wordQuiz" || event.kind === "meaningQuiz");
  return {
    correct: tests.reduce((sum, event) => sum + (event.score ?? 0), 0),
    total: tests.reduce((sum, event) => sum + (event.total ?? 0), 0),
  };
}

// 点は Mac と同じ数え方。記録に点があればそれを使い、単語テストは1問正解で10点
export const POINTS_PER_CORRECT_ANSWER = 10;

export function pointsOf(event: ActivityEvent): number {
  if (event.points !== undefined) return event.points;
  if (event.kind === "wordQuiz" || event.kind === "meaningQuiz") return (event.score ?? 0) * POINTS_PER_CORRECT_ANSWER;
  return 0;
}

export const totalPoints = (events: ActivityEvent[]) => events.reduce((sum, event) => sum + pointsOf(event), 0);

// 覚えた表現を英語のまま残した訳で、英語の文字の割合。score が英語の文字数、total が訳の文字数
export function englishRate(events: ActivityEvent[]): number | null {
  const reads = events.filter((event) => event.kind === "glossRead");
  const total = reads.reduce((sum, event) => sum + (event.total ?? 0), 0);
  return total ? Math.round((reads.reduce((sum, event) => sum + (event.score ?? 0), 0) * 100) / total) : null;
}

export function averageScore(events: ActivityEvent[], kind: ActivityKind): number | null {
  const scores = events.filter((event) => event.kind === kind && event.score !== undefined).map((event) => event.score!);
  return scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : null;
}

// 何日続けて学習しているか。今日まだ何もしていなければ、昨日までで数える
export function streak(events: ActivityEvent[], today = new Date()): number {
  const days = new Set(events.map((event) => dayKey(new Date(event.date))));
  const cursor = startOfDay(today);
  if (!days.has(dayKey(cursor))) cursor.setDate(cursor.getDate() - 1);
  let count = 0;
  while (days.has(dayKey(cursor))) {
    count += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return count;
}

export function lastDays(count: number, today = new Date()): Date[] {
  return Array.from({ length: count }, (_, i) => {
    const day = startOfDay(today);
    day.setDate(day.getDate() - (count - 1 - i));
    return day;
  });
}

export function dailyCounts(events: ActivityEvent[], days: Date[]): number[] {
  return days.map((day) => eventsOn(events, day).length);
}

// 単語帳の語数を、追加した日で積み上げる
export function bookSize(words: WordEntry[], days: Date[]): number[] {
  return days.map((day) => {
    const end = startOfDay(day).getTime() + 86_400_000;
    return words.filter((word) => millis(word.date) < end).length;
  });
}
