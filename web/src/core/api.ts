import type { ActivityRow, WordRow } from "./sync";
import type { Direction } from "./models";

export class Unauthorized extends Error {}

export interface Page<Row> {
  cursor: number;
  hasMore: boolean;
  rows: Row[];
}

export const MAX_ROWS_PER_PUSH = 100;

export function createApi(token: string) {
  async function send(path: string, init: RequestInit = {}) {
    const response = await fetch(path, {
      ...init,
      headers: { Authorization: `Bearer ${token}`, ...(init.body ? { "Content-Type": "application/json" } : {}) },
    });
    if (response.status === 401) throw new Unauthorized();
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }

  return {
    async pullWords(since: number): Promise<Page<WordRow>> {
      const body = await send(`/api/words?since=${since}`);
      return { cursor: body.cursor, hasMore: body.hasMore, rows: body.words };
    },
    pushWords: (rows: WordRow[]) => send("/api/words", { method: "POST", body: JSON.stringify({ words: rows }) }),
    async pullActivity(since: number): Promise<Page<ActivityRow>> {
      const body = await send(`/api/activity?since=${since}`);
      return { cursor: body.cursor, hasMore: body.hasMore, rows: body.events };
    },
    pushActivity: (rows: ActivityRow[]) => send("/api/activity", { method: "POST", body: JSON.stringify({ events: rows }) }),
    async gradeWordTest(
      direction: Direction,
      items: { number: number; prompt: string; expected: string; answer: string }[],
    ): Promise<Record<string, { verdict: number; comment: string }>> {
      const body = await send("/api/ai/word-test", { method: "POST", body: JSON.stringify({ direction, items }) });
      return body.grades;
    },
  };
}

export type Api = ReturnType<typeof createApi>;
