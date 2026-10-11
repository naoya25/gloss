import { create } from "zustand";
import { millis } from "../../core/ids";
import type { WordEntry } from "../../core/models";

export type Face = "english" | "japanese";
export type Sort = "stale" | "fewestFlips" | "mastery" | "newest" | "alphabetical" | "random";

export const sortLabels: Record<Sort, string> = {
  stale: "Least Recently Seen",
  fewestFlips: "Fewest Flips",
  mastery: "Least Known",
  newest: "Newest",
  alphabetical: "A to Z",
  random: "Random",
};

// 並び順は開いたときと並べ替えたときだけ決め直す。めくるたびに並べ直すと、開いたカードが目の前から逃げるため
const englishText = (word: WordEntry) => word.english || word.term;

export function sortWords(words: WordEntry[], sort: Sort): string[] {
  if (sort === "random") return shuffle(words.map((word) => word.id));
  return [...words]
    .sort((a, b) => {
      const diff =
        sort === "stale" ? millis(a.lastReviewed) - millis(b.lastReviewed)
        : sort === "fewestFlips" ? (a.flips ?? 0) - (b.flips ?? 0)
        : sort === "mastery" ? (a.mastery ?? 0) - (b.mastery ?? 0)
        : sort === "alphabetical" ? englishText(a).localeCompare(englishText(b), "en", { sensitivity: "base" })
        : 0;
      return diff !== 0 ? diff : millis(b.date) - millis(a.date);
    })
    .map((word) => word.id);
}

function shuffle<T>(items: T[]): T[] {
  for (let i = items.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    const picked = items[j]!;
    items[j] = items[i]!;
    items[i] = picked;
  }
  return items;
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
