import { create } from "zustand";
import { MAX_ROWS_PER_PUSH } from "../core/api";
import { isoSeconds, newID } from "../core/ids";
import type { ActivityEvent } from "../core/models";
import { load, save } from "../core/storage";
import { activityRow, mergeActivity, type ActivityLedger } from "../core/sync";
import { currentApi, handleSyncError } from "./sync";

interface ActivityState {
  events: ActivityEvent[];
  ledger: ActivityLedger;
  init: () => Promise<void>;
  sync: () => Promise<void>;
  record: (event: Omit<ActivityEvent, "id" | "date">) => void;
}

let pushTimer: ReturnType<typeof setTimeout> | undefined;
let syncing = false;
let syncAgain = false;

// 学習の記録は Cloudflare の activity テーブルを正とする。ここは控え
export const useActivity = create<ActivityState>()((setState, getState) => {
  function persist() {
    void save("activity", getState().events);
    void save("activity-ledger", getState().ledger);
  }

  return {
    events: [],
    ledger: { cursor: 0, pending: [] },
    async init() {
      const [events, ledger] = await Promise.all([
        load<ActivityEvent[]>("activity", []),
        load<ActivityLedger>("activity-ledger", { cursor: 0, pending: [] }),
      ]);
      setState({ events, ledger });
      await getState().sync();
    },
    async sync() {
      const api = currentApi();
      if (!api) return;
      if (syncing) {
        syncAgain = true;
        return;
      }
      syncing = true;
      try {
        do {
          syncAgain = false;
          const pending = new Set(getState().ledger.pending);
          const rows = getState().events.filter((event) => pending.has(event.id)).map(activityRow);
          for (let i = 0; i < rows.length; i += MAX_ROWS_PER_PUSH) {
            const batch = rows.slice(i, i + MAX_ROWS_PER_PUSH);
            await api.pushActivity(batch);
            const sent = new Set(batch.map((row) => row.id));
            setState((state) => ({ ledger: { ...state.ledger, pending: state.ledger.pending.filter((id) => !sent.has(id)) } }));
            persist();
          }
          let hasMore = true;
          while (hasMore) {
            const page = await api.pullActivity(getState().ledger.cursor);
            setState((state) => ({ events: mergeActivity(state.events, page.rows), ledger: { ...state.ledger, cursor: page.cursor } }));
            hasMore = page.hasMore;
            persist();
          }
        } while (syncAgain);
      } catch (error) {
        handleSyncError(error);
      } finally {
        syncing = false;
      }
    },
    record(event) {
      const full: ActivityEvent = { ...event, id: newID(), date: isoSeconds() };
      setState((state) => ({ events: [...state.events, full], ledger: { ...state.ledger, pending: [...state.ledger.pending, full.id] } }));
      persist();
      clearTimeout(pushTimer);
      pushTimer = setTimeout(() => void getState().sync(), 1000);
    },
  };
});
