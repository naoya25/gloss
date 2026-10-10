import { isoSeconds, millis } from "./ids";
import type { ActivityEvent, WordEntry } from "./models";

export interface WordRow {
  id: string;
  updatedAt: number;
  deleted: boolean;
  data: WordEntry | null;
}

export interface ActivityRow {
  id: string;
  kind: string;
  date: number;
  wordID?: string;
  data: ActivityEvent;
}

// まだ送れていない変更(id → 変えた時刻のミリ秒)と、どこまで取ってきたか
export interface WordLedger {
  cursor: number;
  pending: Record<string, number>;
}

export interface ActivityLedger {
  cursor: number;
  pending: string[];
}

export function wordRows(words: WordEntry[], ledger: WordLedger): WordRow[] {
  const byID = new Map(words.map((word) => [word.id, word]));
  return Object.entries(ledger.pending).map(([id, updatedAt]) => {
    const word = byID.get(id);
    return { id, updatedAt, deleted: !word, data: word ?? null };
  });
}

// 送っている間にまた変わった単語は、次にもう一度送る
export function didPushWords(ledger: WordLedger, rows: WordRow[]): WordLedger {
  const pending = { ...ledger.pending };
  for (const row of rows) if (pending[row.id] === row.updatedAt) delete pending[row.id];
  return { ...ledger, pending };
}

// 単語ごとに新しいほうを残す。まだ送っていない手元の変更が新しければ、それを残す(Mac の WordSync.merge と同じ)
export function mergeWords(local: WordEntry[], rows: WordRow[], ledger: WordLedger): WordEntry[] {
  const words = [...local];
  for (const row of rows) {
    const mine = ledger.pending[row.id];
    if (mine !== undefined && mine >= row.updatedAt) continue;
    const index = words.findIndex((word) => word.id.toUpperCase() === row.id.toUpperCase());
    if (index >= 0 && millis(words[index]!.updatedAt) >= row.updatedAt) continue;
    if (row.deleted || !row.data) {
      if (index >= 0) words.splice(index, 1);
      continue;
    }
    const entry = { ...row.data, updatedAt: isoSeconds(new Date(row.updatedAt)) };
    if (index >= 0) words[index] = entry;
    else words.unshift(entry);
  }
  return words;
}

// 記録は書き換えないので、まだ持っていないものを足すだけ
export function mergeActivity(local: ActivityEvent[], rows: ActivityRow[]): ActivityEvent[] {
  const known = new Set(local.map((event) => event.id.toUpperCase()));
  const added = rows.map((row) => row.data).filter((event) => !known.has(event.id.toUpperCase()));
  if (!added.length) return local;
  return [...local, ...added].sort((a, b) => millis(a.date) - millis(b.date));
}

export function activityRow(event: ActivityEvent): ActivityRow {
  return { id: event.id, kind: event.kind, date: millis(event.date), wordID: event.wordID, data: event };
}
