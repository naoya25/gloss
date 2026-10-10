// Mac の GlossCore と同じ形の JSON。項目を足すときは Mac 側と合わせる

export enum Mastery {
  NotYet = 0,
  Unsure = 1,
  Known = 2,
}

export const masteryLabel: Record<Mastery, string> = {
  [Mastery.NotYet]: "Not Yet",
  [Mastery.Unsure]: "Unsure",
  [Mastery.Known]: "Known",
};

// Mac が足した知らない項目も、書き戻すときに消さないよう残す
export interface WordEntry {
  id: string;
  date: string;
  term: string;
  note: string;
  context: string;
  english?: string;
  japanese?: string;
  example?: string;
  exampleTranslation?: string;
  flips?: number;
  lastReviewed?: string;
  mastery?: Mastery;
  updatedAt?: string;
  [key: string]: unknown;
}

export type ActivityKind = "translated" | "wordSaved" | "cardFlipped" | "wordQuiz" | "meaningQuiz" | "writing" | "reading";

export const activityLabel: Record<ActivityKind, string> = {
  translated: "Translated",
  wordSaved: "Saved a word",
  cardFlipped: "Flipped a card",
  wordQuiz: "Word Test",
  meaningQuiz: "Meaning Test",
  writing: "Writing Test",
  reading: "Reading Test",
};

export interface WordAnswer {
  wordID: string;
  prompt: string;
  answer: string;
  verdict: Mastery;
}

export interface ActivityEvent {
  id: string;
  date: string;
  kind: ActivityKind;
  title: string;
  score?: number;
  total?: number;
  detail?: string;
  wordID?: string;
  answer?: string;
  answers?: WordAnswer[];
}

export type Direction = "toEnglish" | "toJapanese";

export const hasCardPair = (word: WordEntry) => !!word.english && !!word.japanese;

export function promptFor(word: WordEntry, direction: Direction): string {
  return direction === "toEnglish" ? word.japanese || word.term : word.english || word.term;
}

export function expectedFor(word: WordEntry, direction: Direction): string {
  return direction === "toEnglish" ? word.english || word.term : word.japanese || word.term;
}
