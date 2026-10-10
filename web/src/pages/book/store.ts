import { create } from "zustand";
import { millis } from "../../core/ids";
import type { WordEntry } from "../../core/models";

export type Face = "english" | "japanese";
export type Sort = "stale" | "fewestFlips" | "mastery" | "newest";

export const sortLabels: Record<Sort, string> = {
  stale: "Least Recently Seen",
  fewestFlips: "Fewest Flips",
  mastery: "Least Known",
  newest: "Newest",
};

// 並び順は開いたときと並べ替えたときだけ決め直す。めくるたびに並べ直すと、開いたカードが目の前から逃げるため
export function sortWords(words: WordEntry[], sort: Sort): string[] {
  return [...words]
    .sort((a, b) => {
      const diff =
        sort === "stale" ? millis(a.lastReviewed) - millis(b.lastReviewed)
        : sort === "fewestFlips" ? (a.flips ?? 0) - (b.flips ?? 0)
        : sort === "mastery" ? (a.mastery ?? 0) - (b.mastery ?? 0)
        : 0;
      return diff !== 0 ? diff : millis(b.date) - millis(a.date);
    })
    .map((word) => word.id);
}

interface BookState {
  face: Face;
  sort: Sort;
  order: string[];
  openID: string | null;
  setFace: (face: Face) => void;
  setSort: (sort: Sort, words: WordEntry[]) => void;
  refresh: (words: WordEntry[]) => void;
  toggle: (id: string) => boolean;
}

export const useBook = create<BookState>()((setState, getState) => ({
  face: "english",
  sort: "stale",
  order: [],
  openID: null,
  setFace: (face) => setState({ face, openID: null }),
  setSort: (sort, words) => setState({ sort, openID: null, order: sortWords(words, sort) }),
  refresh: (words) => setState({ order: sortWords(words, getState().sort), openID: null }),
  // 開いているカードをもう一度押すと閉じる。押したあとにそのカードが開いているかを返す
  toggle(id) {
    const opening = getState().openID !== id;
    setState({ openID: opening ? id : null });
    return opening;
  },
}));
