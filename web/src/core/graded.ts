// 5段階の訳(Mac の GradedTranslation と同じ組み立て)。AI に1回だけ訳してもらい、語句ごとに英語と日本語の両方を持っておく。
// 段階を変えても AI を呼び直さない

export type Level = 90 | 50 | 30 | 10 | 0;
export const LEVELS: { level: Level; label: string }[] = [
  { level: 90, label: "90%" },
  { level: 50, label: "50%" },
  { level: 30, label: "30%" },
  { level: 10, label: "10%" },
  { level: 0, label: "日本語" },
];

export interface Phrase {
  english: string;
  japanese: string;
  // AI が付けたやさしさ(1 やさしい〜5 難しい)。Book で ✓ の語は 0
  difficulty: number;
  learned: boolean;
}

export type Segment = { plain: string } | { phrase: Phrase };

export interface Graded {
  segments: Segment[];
  source: string;
}

// 訳の中で英語のまま読む語句1つ。start と end は text の中の位置
export interface Kept {
  start: number;
  end: number;
  english: string;
  japanese: string;
  learned: boolean;
}

export interface Rendered {
  text: string;
  kept: Kept[];
  // 押すと日本語になる、英語のままの語句。90% では色を付けない語句も入る
  clickable: Kept[];
  // 押して日本語にした語句。start と end は日本語(90% は「英語（日本語）」)の位置で、もう一度押すと英語に戻る
  revealed: Kept[];
  englishCharacters: number;
  totalCharacters: number;
  englishRate: number;
}

const OPEN = "⟦";
const CLOSE = "⟧";
const isJapanese = (char: string) => /[぀-ヿ一-鿿ｦ-ﾟ]/.test(char);
const isLetter = (char: string) => /\p{L}/u.test(char);
const nonSpace = (text: string) => text.replace(/\s/g, "").length;
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// 「Hi」が「this」の中に当たらないように、前後が英字でない場所だけを探す
export function containsWord(word: string, text: string): boolean {
  return new RegExp(`(?<![A-Za-z])${escape(word)}(?![A-Za-z])`, "i").test(text);
}

// 動詞は原形で書かせるので、英文の中では活用した形(pushed, migrating)で出てくることがある。その形も探す
export function appears(english: string, source: string): boolean {
  if (containsWord(english, source)) return true;
  const words = english.split(" ");
  const first = words[0];
  if (!first) return false;
  const stem = first.endsWith("e") ? first.slice(0, -1) : first;
  const last = first.slice(-1);
  return [`${first}s`, `${first}es`, `${first}d`, `${first}ed`, `${stem}ing`, `${first}${last}ed`, `${first}${last}ing`].some((form) =>
    containsWord([form, ...words.slice(1)].join(" "), source),
  );
}

// AI は語句を「⟦hotfix | 緊急修正 | 4⟧」の形で書く。書きかけの「⟦…」は出さない。英文に無い語句は日本語のままにする
export function parseGraded(raw: string, known: string[], source: string): Graded {
  const knownKeys = new Set(known.map((term) => term.toLowerCase()));
  const segments: Segment[] = [];
  let rest = raw;
  for (;;) {
    const start = rest.indexOf(OPEN);
    if (start < 0) break;
    if (start > 0) segments.push({ plain: rest.slice(0, start) });
    const end = rest.indexOf(CLOSE, start);
    if (end < 0) {
      rest = "";
      break;
    }
    const parts = rest.slice(start + 1, end).split("|").map((part) => part.trim());
    const english = parts[0] ?? "";
    const japanese = parts[1] ?? english;
    const learned = knownKeys.has(english.toLowerCase());
    if (!english || !appears(english, source)) {
      segments.push({ plain: japanese });
    } else {
      const difficulty = learned ? 0 : Number.parseInt(parts[2] ?? "", 10) || 3;
      segments.push({ phrase: { english, japanese, difficulty, learned } });
    }
    rest = rest.slice(end + 1);
  }
  if (rest) segments.push({ plain: rest });
  return { segments, source };
}

// 長い英文は、空行で区切った段落を limit 文字ほどずつにまとめて、別々に訳してもらう。
// 一度に長い文を頼むと、AI が語句の印を付け忘れるため
export function splitParts(source: string, limit = 1200): string[] {
  const parts: string[] = [];
  let current = "";
  for (const paragraph of source.split("\n\n").filter((p) => p.trim())) {
    if (current && current.length + paragraph.length > limit) {
      parts.push(current);
      current = "";
    }
    current += current ? `\n\n${paragraph}` : paragraph;
  }
  if (current) parts.push(current);
  return parts.length ? parts : [source];
}

export function joinGraded(parts: Graded[], source: string): Graded {
  const segments: Segment[] = [];
  for (const part of parts) {
    if (segments.length) segments.push({ plain: "\n\n" });
    segments.push(...part.segments);
  }
  return { segments, source };
}

export const phrasesOf = (graded: Graded): Phrase[] => graded.segments.flatMap((segment) => ("phrase" in segment ? [segment.phrase] : []));

export function japaneseOf(graded: Graded): string {
  return graded.segments.map((segment) => ("phrase" in segment ? segment.phrase.japanese : segment.plain)).join("");
}

// revealed は読みながら押して日本語にした語句(小文字の英語)
export function render(graded: Graded, level: Level, revealed: Set<string> = new Set()): Rendered {
  if (level === 0) return mixed(graded, new Set());
  if (level === 90) return englishBased(graded, revealed);
  return japaneseBased(graded, level, revealed);
}

// 英語で出した語句のうち、押さずに英語のまま読めた割合を、段階と同じ物差し(0〜100)で返す(Mac の readAbility と同じ)。
// 50% で出して半分の語句を押したら 25。日本語の段階は 0
export function readAbility(graded: Graded, level: Level, revealed: Set<string>): number {
  if (level === 0) return 0;
  const shown = render(graded, level).clickable;
  const total = shown.reduce((sum, item) => sum + nonSpace(item.english), 0);
  if (!total) return level;
  const read = shown.filter((item) => !revealed.has(item.english.toLowerCase())).reduce((sum, item) => sum + nonSpace(item.english), 0);
  return Math.floor((level * read) / total);
}

// 英語のまま読めた割合より1段上の段階。実力よりちょっと英語が多い訳で次の英文を読み、押した分だけ下がる
export function levelAbove(ability: number): Level {
  return ([0, 10, 30, 50, 90] as Level[]).find((level) => level > ability) ?? 90;
}

// ✓ の語は必ず英語にし、残りはやさしい語句から順に、英語に戻せる語句(の文字数)の level% まで英語に戻す
function japaneseBased(graded: Graded, level: number, revealed: Set<string>): Rendered {
  const phrases = phrasesOf(graded);
  const size = phrases.map((phrase) => nonSpace(phrase.english));
  const goal = (size.reduce((a, b) => a + b, 0) * level) / 100;
  const keep = new Set(phrases.flatMap((phrase, i) => (phrase.learned ? [i] : [])));
  let kept = [...keep].reduce((sum, i) => sum + size[i]!, 0);
  const order = phrases.map((_, i) => i).sort((a, b) => phrases[a]!.difficulty - phrases[b]!.difficulty);
  for (const i of order) {
    if (keep.has(i)) continue;
    if (kept >= goal) break;
    // 足すと目標から遠ざかるほど長い語句は、飛ばして次の短い語句を試す
    const next = kept + size[i]!;
    if (next - goal > goal - kept) continue;
    keep.add(i);
    kept = next;
  }
  return mixed(graded, keep, revealed);
}

// 日本語の文に、keep の語句だけ英語で入れる。日本語と英語がくっつくと切れ目が見えないので、間に空白を入れる
// shown のうち押した語句(revealed)は日本語に戻し、もう一度押せるよう位置を持つ
function mixed(graded: Graded, shown: Set<number>, revealed: Set<string> = new Set()): Rendered {
  let text = "";
  const kept: Kept[] = [];
  const back: Kept[] = [];
  let spacesNext = false;
  let index = -1;
  for (const segment of graded.segments) {
    const isShown = "phrase" in segment && shown.has(++index);
    const isBack = isShown && "phrase" in segment && revealed.has(segment.phrase.english.toLowerCase());
    const isKept = isShown && !isBack;
    if ("phrase" in segment && isKept) {
      const { english, japanese, learned } = segment.phrase;
      const last = text.slice(-1);
      if (last && (isJapanese(last) || isLetter(last))) text += " ";
      kept.push({ start: text.length, end: text.length + english.length, english, japanese, learned });
      text += english;
      spacesNext = true;
    } else {
      const piece = "phrase" in segment ? segment.phrase.japanese : segment.plain;
      if (spacesNext && piece && isJapanese(piece[0]!)) text += " ";
      spacesNext = false;
      if (isBack && "phrase" in segment) {
        const { english, japanese, learned } = segment.phrase;
        back.push({ start: text.length, end: text.length + piece.length, english, japanese, learned });
      }
      text += piece;
    }
  }
  const englishCharacters = kept.reduce((sum, item) => sum + nonSpace(item.english), 0);
  const totalCharacters = nonSpace(text);
  return { text, kept, clickable: kept, revealed: back, englishCharacters, totalCharacters, englishRate: totalCharacters ? Math.floor((englishCharacters * 100) / totalCharacters) : 0 };
}

// 原文のまま読み、難しい語句から順に、全体の 1 割ほどまで日本語を添える。押した語句にも日本語を添える。
// 日本語を添えていない語句は押せるようにし、✓ の語は色を付けて見せる
function englishBased(graded: Graded, revealed: Set<string>): Rendered {
  let text = graded.source;
  const total = nonSpace(graded.source);
  const unglossed = (english: string) => new RegExp(`(?<![A-Za-z])${escape(english)}(?![A-Za-z])(?!（)`, "i");
  const gloss = (phrase: Phrase) => {
    const match = unglossed(phrase.english).exec(text);
    if (!match) return 0;
    const note = `（${phrase.japanese}）`;
    const at = match.index + match[0].length;
    text = text.slice(0, at) + note + text.slice(at);
    return note.length;
  };
  let glossed = 0;
  const phrases = phrasesOf(graded);
  const hardFirst = phrases.filter((phrase) => !phrase.learned).sort((a, b) => b.difficulty - a.difficulty);
  for (const phrase of hardFirst) {
    if (glossed * 10 >= total) break;
    glossed += gloss(phrase);
  }
  for (const phrase of phrases) if (revealed.has(phrase.english.toLowerCase())) gloss(phrase);
  const back: Kept[] = [];
  for (const phrase of phrases) {
    if (!revealed.has(phrase.english.toLowerCase()) || back.some((item) => item.english === phrase.english)) continue;
    const match = new RegExp(`(?<![A-Za-z])${escape(phrase.english)}（${escape(phrase.japanese)}）`, "i").exec(text);
    if (match) back.push({ start: match.index, end: match.index + match[0].length, english: phrase.english, japanese: phrase.japanese, learned: phrase.learned });
  }
  const clickable: Kept[] = [];
  for (const phrase of phrases) {
    if (clickable.some((item) => item.english.toLowerCase() === phrase.english.toLowerCase())) continue;
    const match = unglossed(phrase.english).exec(text);
    if (match) clickable.push({ start: match.index, end: match.index + match[0].length, english: phrase.english, japanese: phrase.japanese, learned: phrase.learned });
  }
  const englishCharacters = (text.match(/[A-Za-z0-9]/g) ?? []).length;
  const totalCharacters = nonSpace(text);
  return {
    text,
    kept: clickable.filter((item) => item.learned),
    clickable,
    revealed: back,
    englishCharacters,
    totalCharacters,
    englishRate: totalCharacters ? Math.floor((englishCharacters * 100) / totalCharacters) : 0,
  };
}

// 英語のまま読んだ点。覚えた語は1語ごとに 10 点、ほかは英語の割合 10% ごとに 5 点(Mac の readingPoints と同じ)
export function readingPoints(rendered: Rendered, level: Level): number {
  if (level === 0) return 0;
  const learned = new Set(rendered.kept.filter((item) => item.learned).map((item) => item.english.toLowerCase())).size;
  return learned * 10 + Math.floor(rendered.englishRate / 10) * 5;
}

// 日本語をほとんど含まない英文だけを、5段階で訳す
export function isEnglish(text: string): boolean {
  const latin = (text.match(/[A-Za-z]/g) ?? []).length;
  const japanese = [...text].filter(isJapanese).length;
  return latin >= 10 && japanese * 20 < latin;
}
