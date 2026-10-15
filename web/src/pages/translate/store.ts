import { create } from "zustand";
import { containsWord, isEnglish, joinGraded, nextLevel, parseGraded, phrasesOf, readAbility, render, readingPoints, splitParts, type Graded, type Level } from "../../core/graded";
import { Mastery } from "../../core/models";
import { useActivity } from "../../stores/activity";
import { currentApi } from "../../stores/sync";
import { useWords } from "../../stores/words";

const LEVEL_KEY = "gloss-english-level";
// 今の段階で読んだ直近の英文の、英語のまま読めた割合。段階が変わったら空にする
const RECENT_KEY = "gloss-english-recent";

function savedLevel(): Level {
  try {
    const value = Number(localStorage.getItem(LEVEL_KEY));
    return ([90, 50, 30, 10, 0] as Level[]).includes(value as Level) ? (value as Level) : 30;
  } catch {
    return 30;
  }
}

export function savedRecent(): number[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(RECENT_KEY) ?? "[]");
    return Array.isArray(value) ? value.filter((item): item is number => typeof item === "number") : [];
  } catch {
    return [];
  }
}

function storeLevel(level: Level, recent: number[] = []) {
  try {
    localStorage.setItem(LEVEL_KEY, String(level));
    localStorage.setItem(RECENT_KEY, JSON.stringify(recent));
  } catch {
    // 保存できなくても、この画面では選んだ段階で読める
  }
}

interface TranslateState {
  source: string;
  graded: Graded | null;
  level: Level;
  translating: boolean;
  // 訳せた段落のまとまりの数と、全部の数
  progress: [number, number];
  error: string | null;
  // 記録したか。次の英文を訳すとき・New を押したとき・ページを閉じたときに1回だけ記録する
  read: boolean;
  // 読みながら押して日本語にした語句(小文字の英語)
  revealed: Set<string>;
  setSource: (text: string) => void;
  setLevel: (level: Level) => void;
  reveal: (english: string) => void;
  translate: () => Promise<void>;
  recordReading: () => void;
  reset: () => void;
}

// 英文を段落のまとまりごとに順に訳し、訳せた分から出す。Mac の TranslateStore と同じ流れ
export const useTranslate = create<TranslateState>()((setState, getState) => ({
  source: "",
  graded: null,
  level: savedLevel(),
  translating: false,
  progress: [0, 0],
  error: null,
  read: false,
  revealed: new Set(),
  setSource: (source) => setState({ source }),
  setLevel(level) {
    setState({ level });
    storeLevel(level);
  },
  // 押した語句を日本語にする。日本語にした語句をもう一度押すと英語に戻す
  reveal(english) {
    if (getState().read) return;
    const key = english.toLowerCase();
    setState((state) => {
      const revealed = new Set(state.revealed);
      if (!revealed.delete(key)) revealed.add(key);
      return { revealed };
    });
  },
  reset() {
    getState().recordReading();
    setState({ source: "", graded: null, translating: false, progress: [0, 0], error: null, read: false, revealed: new Set() });
  },
  async translate() {
    const source = getState().source.trim();
    if (!source || getState().translating) return;
    if (!isEnglish(source)) {
      setState({ error: "Paste English text. Text with much Japanese can't be read in levels." });
      return;
    }
    const api = currentApi();
    if (!api) return;
    const known = useWords
      .getState()
      .words.filter((word) => word.mastery === Mastery.Known)
      .map((word) => word.english || word.term)
      .filter((term) => containsWord(term, source));
    const parts = splitParts(source);
    getState().recordReading();
    setState({ graded: null, level: savedLevel(), translating: true, progress: [0, parts.length], error: null, read: false, revealed: new Set() });
    const done: Graded[] = [];
    try {
      for (const part of parts) {
        const raw = await api.translate(part, known);
        if (getState().source.trim() !== source) return;
        done.push(parseGraded(raw, known, part));
        setState({ graded: joinGraded(done, source), progress: [done.length, parts.length] });
      }
      useActivity.getState().record({ kind: "translated", title: source.slice(0, 60) });
    } catch {
      setState({ error: navigator.onLine ? "Couldn't reach the AI. Try again." : "You're offline." });
    } finally {
      setState({ translating: false });
    }
  },
  // 読み終えた分を記録する(Mac の recordReading と同じ)。次の英文の段階は nextLevel で決め、
  // 押した語句は Book で ? にする(Book に無い語句は Mac で入る)
  recordReading() {
    const { graded, level, read, revealed, source, translating } = getState();
    if (!graded || read || translating || !phrasesOf(graded).length) return;
    const rendered = render(graded, level, revealed);
    setState({ read: true });
    useActivity.getState().record({
      kind: "glossRead",
      title: source.slice(0, 60),
      score: level === 0 ? 0 : rendered.englishCharacters,
      total: rendered.totalCharacters,
      detail: `${level === 0 ? "日本語" : `${level}%`} · ${[...new Set(rendered.kept.map((item) => item.english))].join(", ")}`,
      points: readingPoints(rendered, level),
    });
    // 今の訳の段階は変えず、次の英文から使う
    const next = nextLevel(level, readAbility(graded, level, revealed), savedRecent());
    storeLevel(next.level, next.recent);
    const words = useWords.getState();
    for (const word of words.words) {
      const term = (word.english || word.term).toLowerCase();
      if (revealed.has(term) && word.mastery !== Mastery.NotYet && word.mastery !== Mastery.Unsure) words.setMastery(word.id, Mastery.Unsure);
    }
  },
}));
