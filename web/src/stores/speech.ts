import { create } from "zustand";
import type { WordEntry } from "../core/models";
import { say } from "../core/speech";

interface SpeechState {
  speakingID: string | null;
  listening: boolean;
  speak: (word: WordEntry) => void;
  listen: (words: WordEntry[]) => void;
  stop: () => void;
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
let run = 0;

// 単語 → 例文の順に読む。新しく読み始めたら run が変わるので、前の読み上げは続きを読まない
async function read(word: WordEntry, token: number, set: (state: Partial<SpeechState>) => void) {
  set({ speakingID: word.id });
  await say(word.english || word.term);
  if (word.example && token === run) {
    await wait(600);
    if (token === run) await say(word.example);
  }
}

export const useSpeech = create<SpeechState>((set, get) => ({
  speakingID: null,
  listening: false,
  speak: (word) => {
    get().stop();
    const token = ++run;
    void read(word, token, set).then(() => {
      if (token === run) set({ speakingID: null });
    });
  },
  listen: (words) => {
    get().stop();
    const token = ++run;
    set({ listening: true });
    void (async () => {
      for (const word of words) {
        if (token !== run) return;
        await read(word, token, set);
        await wait(1200);
      }
      if (token === run) set({ speakingID: null, listening: false });
    })();
  },
  stop: () => {
    run += 1;
    speechSynthesis.cancel();
    set({ speakingID: null, listening: false });
  },
}));
