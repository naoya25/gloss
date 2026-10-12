import { create } from "zustand";
import { containsWord, isEnglish, joinGraded, parseGraded, render, readingPoints, splitParts, type Graded, type Level } from "../../core/graded";
import { Mastery } from "../../core/models";
import { useActivity } from "../../stores/activity";
import { currentApi } from "../../stores/sync";
import { useWords } from "../../stores/words";

const LEVEL_KEY = "gloss-english-level";

function savedLevel(): Level {
  try {
    const value = Number(localStorage.getItem(LEVEL_KEY));
    return ([90, 50, 30, 10, 0] as Level[]).includes(value as Level) ? (value as Level) : 30;
  } catch {
    return 30;
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
  read: boolean;
  setSource: (text: string) => void;
  setLevel: (level: Level) => void;
  translate: () => Promise<void>;
  markRead: () => void;
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
  setSource: (source) => setState({ source }),
  setLevel(level) {
    setState({ level });
    try {
      localStorage.setItem(LEVEL_KEY, String(level));
    } catch {
      // 保存できなくても、この画面では選んだ段階で読める
    }
  },
  reset: () => setState({ source: "", graded: null, translating: false, progress: [0, 0], error: null, read: false }),
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
    setState({ graded: null, translating: true, progress: [0, parts.length], error: null, read: false });
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
  // 読み終えた時点で記録に残す。英語の割合は、読んだ段階の訳で数える
  markRead() {
    const { graded, level, read, source } = getState();
    if (!graded || read) return;
    const rendered = render(graded, level);
    setState({ read: true });
    useActivity.getState().record({
      kind: "glossRead",
      title: source.slice(0, 60),
      score: level === 0 ? 0 : rendered.englishCharacters,
      total: rendered.totalCharacters,
      detail: `${level === 0 ? "日本語" : `${level}%`} · ${[...new Set(rendered.kept.map((item) => item.english))].join(", ")}`,
      points: readingPoints(rendered, level),
    });
  },
}));
