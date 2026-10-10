import { create } from "zustand";
import { MAX_ROWS_PER_PUSH } from "../core/api";
import { isoSeconds } from "../core/ids";
import type { Mastery, WordEntry } from "../core/models";
import { load, save } from "../core/storage";
import { didPushWords, mergeWords, wordRows, type WordLedger } from "../core/sync";
import { currentApi, handleSyncError } from "./sync";

interface WordsState {
  words: WordEntry[];
  ledger: WordLedger;
  loaded: boolean;
  syncing: boolean;
  syncError: string | null;
  lastSynced: number | null;
  init: () => Promise<void>;
  sync: () => Promise<void>;
  recordFlip: (id: string) => void;
  setMastery: (id: string, mastery: Mastery) => void;
  recordQuizAnswer: (id: string, mastery: Mastery) => void;
}

let pushTimer: ReturnType<typeof setTimeout> | undefined;
let syncAgain = false;

export const useWords = create<WordsState>()((setState, getState) => {
  function persist() {
    const { words, ledger } = getState();
    void save("words", words);
    void save("words-ledger", ledger);
  }

  // 書き換えた単語に時刻を付けて控えに保存し、少し待ってまとめて Cloudflare に送る
  function change(id: string, patch: (word: WordEntry) => WordEntry) {
    const now = new Date();
    setState((state) => ({
      words: state.words.map((word) => (word.id === id ? { ...patch(word), updatedAt: isoSeconds(now) } : word)),
      ledger: { ...state.ledger, pending: { ...state.ledger.pending, [id]: now.getTime() } },
    }));
    persist();
    clearTimeout(pushTimer);
    pushTimer = setTimeout(() => void getState().sync(), 1000);
  }

  return {
    words: [],
    ledger: { cursor: 0, pending: {} },
    loaded: false,
    syncing: false,
    syncError: null,
    lastSynced: null,
    async init() {
      const [words, ledger] = await Promise.all([load<WordEntry[]>("words", []), load<WordLedger>("words-ledger", { cursor: 0, pending: {} })]);
      setState({ words, ledger, loaded: true });
      await getState().sync();
    },
    // 送れていない変更を送ってから、ほかの端末の変更を取ってくる
    async sync() {
      const api = currentApi();
      if (!api) return;
      if (getState().syncing) {
        syncAgain = true;
        return;
      }
      setState({ syncing: true });
      try {
        do {
          syncAgain = false;
          const rows = wordRows(getState().words, getState().ledger);
          for (let i = 0; i < rows.length; i += MAX_ROWS_PER_PUSH) {
            const batch = rows.slice(i, i + MAX_ROWS_PER_PUSH);
            await api.pushWords(batch);
            setState((state) => ({ ledger: didPushWords(state.ledger, batch) }));
            persist();
          }
          let hasMore = true;
          while (hasMore) {
            const page = await api.pullWords(getState().ledger.cursor);
            setState((state) => ({
              words: mergeWords(state.words, page.rows, state.ledger),
              ledger: { ...state.ledger, cursor: page.cursor },
            }));
            hasMore = page.hasMore;
            persist();
          }
        } while (syncAgain);
        setState({ syncError: null, lastSynced: Date.now() });
      } catch (error) {
        setState({ syncError: handleSyncError(error) });
      } finally {
        setState({ syncing: false });
      }
    },
    recordFlip: (id) => change(id, (word) => ({ ...word, flips: (word.flips ?? 0) + 1, lastReviewed: isoSeconds() })),
    setMastery: (id, mastery) => change(id, (word) => ({ ...word, mastery })),
    recordQuizAnswer: (id, mastery) =>
      change(id, (word) => ({ ...word, mastery, flips: (word.flips ?? 0) + 1, lastReviewed: isoSeconds() })),
  };
});
