import { hasCardPair, Mastery, type Direction, type WordEntry } from "./models";
import { millis } from "./ids";

export const QUESTION_COUNT = 10;

// 覚えていない単語と、しばらく見ていない単語から先に出す(Mac の WordQuiz.pick と同じ)。
// 直前のテストに出した単語は、ほかに出せる単語が足りないときだけ混ぜる
export function pickQuestions(words: WordEntry[], count = QUESTION_COUNT, recent: Set<string> = new Set()): WordEntry[] {
  const candidates = words.filter(hasCardPair);
  const fresh = candidates.filter((word) => !recent.has(word.id));
  const ordered = (fresh.length >= count ? fresh : candidates).sort((a, b) => {
    const mastery = (a.mastery ?? 0) - (b.mastery ?? 0);
    return mastery !== 0 ? mastery : millis(a.lastReviewed) - millis(b.lastReviewed);
  });
  const pool = ordered.slice(0, count * 2);
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j]!, pool[i]!];
  }
  return pool.slice(0, count);
}

function normalizeEnglish(text: string): string {
  return text
    .toLowerCase()
    .replace(/’/g, "'")
    .split(/[^\p{L}\p{N}']+/u)
    .filter(Boolean)
    .join(" ");
}

function normalizeJapanese(text: string): string {
  return text.replace(/[\s\p{P}]/gu, "");
}

// 大文字小文字・記号・空白の違いは間違いにしない。日本語の訳は「・」などで並べた、どれか1つと同じなら正解
export function isExactAnswer(answer: string, word: WordEntry, direction: Direction): boolean {
  if (direction === "toEnglish") {
    const given = normalizeEnglish(answer);
    return given !== "" && [word.english ?? "", word.term].some((value) => normalizeEnglish(value) === given);
  }
  const given = normalizeJapanese(answer);
  return given !== "" && (word.japanese ?? "").split(/[・、,/／;；]/).some((value) => normalizeJapanese(value) === given);
}

export interface Grade {
  verdict: Mastery;
  comment: string;
  // AI が採点できず、自分で付けるまで決まっていない
  pending?: boolean;
}
