import { expectedFor, hasCardPair, promptFor, Mastery, type Direction, type WordEntry } from "./models";
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

// 4択の単語テスト(Mac の ChoiceQuiz と同じ)。記録の種類は書くテストと同じにして、題名で見分ける。
// 種類を増やすと、まだ更新していない Mac が同期で読めなくなるため
export const CHOICE_TITLE = "4-Choice Test";
export const CHOICE_OPTION_COUNT = 4;
// 選ぶのは書くより易しいので、書くテストの1問10点より低くする
export const CHOICE_POINTS_PER_CORRECT = 5;

const optionKey = (text: string) => text.trim().toLowerCase();

function shuffled<T>(items: T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j]!, copy[i]!];
  }
  return copy;
}

// 外れの選択肢も、どの単語の答えなのかを振り返れるように、その単語の問題側の言葉を持つ
export interface ChoiceOption {
  text: string;
  meaning: string;
}

const optionFor = (word: WordEntry, direction: Direction): ChoiceOption => ({ text: expectedFor(word, direction), meaning: promptFor(word, direction) });

// 正解1つと、ほかの単語の答えから選んだ外れを混ぜて並べる。同じ答えの外れは入れない
export function choiceOptions(word: WordEntry, words: WordEntry[], direction: Direction, count = CHOICE_OPTION_COUNT): ChoiceOption[] {
  const answer = optionFor(word, direction);
  const seen = new Set([optionKey(answer.text)]);
  const distractors: ChoiceOption[] = [];
  for (const other of shuffled(words.filter(hasCardPair))) {
    if (distractors.length >= count - 1) break;
    if (other.id === word.id) continue;
    const option = optionFor(other, direction);
    if (seen.has(optionKey(option.text))) continue;
    seen.add(optionKey(option.text));
    distractors.push(option);
  }
  return shuffled([...distractors, answer]);
}

// 選んで当たっても、思い出して書けたとは限らないので、Book の印は1段ずつしか上げない。外したら ✕ に戻す
export function nextMastery(current: Mastery, correct: boolean): Mastery {
  return correct ? Math.min(current + 1, Mastery.Known) : Mastery.NotYet;
}
