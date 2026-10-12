import { TEST_TRENDS, visibleDays, testCounts, latestEnglish, countOn, cumulative, dailyCounts, distinct, englishRates, firstCorrect, formatTest, matchesTest, newlyCorrect, testSeries, testValue } from "./growth";
import type { ActivityEvent, WordEntry } from "./models";
import { countKind, englishRate, eventsOn, lastDays, totalPoints } from "./report";

// 画像には、その日の分のほかに推移と単語も要るので、全部の記録と単語帳を渡す
export interface ShareSummary {
  day: Date;
  streak: number;
  allEvents: ActivityEvent[];
  words: WordEntry[];
}

const pad2 = (n: number) => String(n).padStart(2, "0");
const isoDay = (day: Date) => `${day.getFullYear()}-${pad2(day.getMonth() + 1)}-${pad2(day.getDate())}`;
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const md = (day: Date) => `${day.getMonth() + 1}/${day.getDate()}`;
const DAYS = 14;

// Report の画面に出している数字を1か所で出す。Markdown と画像はこれを並べるだけ
function growthSummary({ day, allEvents, words }: ShareSummary) {
  const today = eventsOn(allEvents, day);
  const reads = today.filter((event) => event.kind === "glossRead");
  const said = distinct(firstCorrect(allEvents, false), words);
  const seen = distinct(firstCorrect(allEvents, true), words);
  const byID = new Map(words.map((word) => [word.id, word]));
  const days = lastDays(visibleDays(DAYS, allEvents, day), day);
  const recent = allEvents.filter((event) => Date.parse(event.date) >= days[0]!.getTime());
  return {
    today,
    rate: englishRate(today),
    texts: reads.length,
    english: reads.reduce((sum, event) => sum + (event.score ?? 0), 0),
    translated: reads.reduce((sum, event) => sum + (event.total ?? 0), 0),
    days,
    trend: englishRates(allEvents, days),
    said,
    seen,
    seenOnly: [...seen.keys()].filter((id) => !said.has(id)).length,
    saidToday: newlyCorrect(said, day).flatMap((id) => byID.get(id) ?? []),
    tests: TEST_TRENDS.map((test) => ({
      test,
      value: testValue(test, recent),
      count: recent.filter((event) => matchesTest(test, event)).length,
      series: testSeries(test, allEvents, days),
      perDay: testCounts(test, allEvents, days),
    })),
    counts: dailyCounts(allEvents),
  };
}

// Mac の GrowthReport.markdown と同じ中身
export function reportMarkdown(summary: ShareSummary): string {
  const { day, streak, allEvents } = summary;
  const g = growthSummary(summary);
  const lines = [`# Gloss Report: ${isoDay(day)} (${WEEKDAYS[day.getDay()]})`];
  if (streak > 0) lines.push(`🔥 ${streak}-day streak`);
  lines.push("", `## Read in English: ${g.rate === null ? "–" : `${g.rate}%`}`);
  lines.push(
    g.rate === null
      ? "No translations read in English today"
      : `How much of today's translations stayed in English (${g.texts} texts, ${g.english} of ${g.translated} chars)`,
  );
  const trend = g.trend.flatMap((value, i) => (value === null ? [] : [`${md(g.days[i]!)} ${Math.round(value)}%`]));
  if (trend.length >= 2) lines.push(`Last ${DAYS} days: ${trend.join(" · ")}`);
  lines.push("", `## Words you can say: ${g.said.size}${g.saidToday.length ? ` (+${g.saidToday.length} today)` : ""}`);
  lines.push(`Words you answered yourself in Word and Meaning Tests. Another ${g.seenOnly} recognized in 4-Choice Tests`);
  if (g.saidToday.length) {
    lines.push("", "### Words you said today", "", ...g.saidToday.map((word) => `- ${word.english ?? word.term} — ${word.japanese ?? word.term}`));
  }
  const testLines = g.tests.flatMap(({ test, value, count }) =>
    value === null ? [] : [`- ${test.label}: ${count} times, ${Math.round(value)}${test.unit === "%" ? "% correct" : " pts on average"}`],
  );
  if (testLines.length) lines.push("", `## Tests (last ${DAYS} days)`, ...testLines);
  const tests = g.today.filter((event) => event.kind === "wordQuiz" || event.kind === "meaningQuiz").length;
  lines.push(
    "",
    "## Today",
    `Translated ${countKind(g.today, "translated")} · Cards flipped ${countKind(g.today, "cardFlipped")} · Words saved ${countKind(g.today, "wordSaved")} · Word tests ${tests} · Writing ${countKind(g.today, "writing")} · Points ${totalPoints(g.today)} (${totalPoints(allEvents)} in total)`,
  );
  return lines.join("\n");
}

const INK = "#1f2328";
const SUB = "#59636e";
const LINE = "#d1d9e0";
const CARD = "#f6f8fa";
const EN = "#2f6bff";
const SEEN = "#b5651d";
const FONT = '-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", sans-serif';
const WIDTH = 640;
const PAD = 28;
const INNER = WIDTH - PAD * 2;

// 画面の Report と同じ並びの画像を描く。貼り先の地の色が分からないので、白地に決め打ち
export async function reportImage(summary: ShareSummary): Promise<Blob> {
  const { day, streak } = summary;
  const g = growthSummary(summary);
  const chartH = 120;
  const cardH = (inner: number) => 16 + 18 + 18 + inner + 16;
  const wordsH = g.saidToday.length ? 40 + Math.ceil(g.saidToday.length / 2) * 50 : 0;
  const height = PAD + 44 + 16 + 150 + 16 + cardH(chartH) + 12 + cardH(chartH + 18) + 12 + cardH(5 * 80 + 14) + 12 + cardH(110) + 16 + wordsH + 40 + PAD;
  const scale = 2;
  const canvas = document.createElement("canvas");
  canvas.width = WIDTH * scale;
  canvas.height = height * scale;
  const ctx = canvas.getContext("2d")!;
  ctx.scale(scale, scale);
  const font = (size: number, weight = 400) => `${weight} ${size}px ${FONT}`;
  const text = (value: string, x: number, y: number, size: number, color = INK, weight = 400, align: CanvasTextAlign = "left") => {
    ctx.font = font(size, weight);
    ctx.fillStyle = color;
    ctx.textAlign = align;
    ctx.fillText(value, x, y);
    ctx.textAlign = "left";
  };
  const box = (x: number, y: number, w: number, h: number) => {
    ctx.fillStyle = CARD;
    ctx.strokeStyle = LINE;
    ctx.beginPath();
    ctx.roundRect(x + 0.5, y + 0.5, w - 1, h - 1, 12);
    ctx.fill();
    ctx.stroke();
  };
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, WIDTH, height);

  let y = PAD;
  text(day.toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", weekday: "short" }), PAD, y + 28, 26, INK, 700);
  if (streak > 0) text(`🔥 ${streak}-day streak`, WIDTH - PAD, y + 26, 14, INK, 600, "right");
  y += 44 + 16;

  // 主役の2つ
  const heroW = (INNER - 12) / 2;
  box(PAD, y, heroW, 150);
  text("Read in English", PAD + 16, y + 26, 12, SUB);
  const latest = g.rate === null ? latestEnglish(summary.allEvents) : null;
  text(g.rate !== null ? `${g.rate}%` : latest ? `${latest.rate}%` : "–", PAD + 16, y + 78, 48, g.rate === null ? SUB : INK, 700);
  if (latest) text(`On ${md(latest.day)}. Nothing yet today.`, PAD + 16, y + 102, 12, SUB);
  if (g.rate !== null) {
    text(`${g.texts} texts translated today`, PAD + 16, y + 102, 12, SUB);
    ctx.fillStyle = LINE;
    ctx.beginPath();
    ctx.roundRect(PAD + 16, y + 118, heroW - 32, 10, 5);
    ctx.fill();
    ctx.fillStyle = EN;
    ctx.beginPath();
    ctx.roundRect(PAD + 16, y + 118, Math.max(6, ((heroW - 32) * g.english) / Math.max(1, g.translated)), 10, 5);
    ctx.fill();
  }
  const hx = PAD + heroW + 12;
  box(hx, y, heroW, 150);
  text("Words you can say", hx + 16, y + 26, 12, SUB);
  text(`${g.said.size}`, hx + 16, y + 78, 48, INK, 700);
  text(g.saidToday.length ? `+${g.saidToday.length} today` : "None new today", hx + 16, y + 102, 13, INK, 600);
  text(`Another ${g.seenOnly} recognized in 4-Choice`, hx + 16, y + 124, 12, SUB);
  y += 150 + 16;

  // 折れ線。null の日は点を打たない
  const line = (x0: number, y0: number, w: number, h: number, values: (number | null)[], max: number, color: string, unit: string, labels: boolean) => {
    const x = (i: number) => x0 + 28 + (i * (w - 36)) / Math.max(1, values.length - 1);
    const yy = (v: number) => y0 + h - 16 - (v / max) * (h - 24);
    if (labels) {
      for (const gv of [0, max / 2, max]) {
        ctx.strokeStyle = "#e6eaee";
        ctx.beginPath();
        ctx.moveTo(x0 + 28, yy(gv));
        ctx.lineTo(x0 + w - 8, yy(gv));
        ctx.stroke();
        text(`${Math.round(gv)}${unit}`, x0 + 22, yy(gv) + 3, 10, SUB, 400, "right");
      }
      g.days.forEach((d, i) => (g.days.length - 1 - i) % 3 === 0 && text(md(d), x(i), y0 + h, 10, SUB, 400, "center"));
    }
    const points = values.flatMap((v, i) => (v === null ? [] : [[x(i), yy(v)] as const]));
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    points.forEach(([px, py], n) => (n ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
    ctx.stroke();
    ctx.lineWidth = 1;
    ctx.fillStyle = color;
    for (const [px, py] of points) {
      ctx.beginPath();
      ctx.arc(px, py, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  };
  const card = (title: string, claim: string, inner: number, draw: (top: number) => void) => {
    const h = cardH(inner);
    box(PAD, y, INNER, h);
    text(title, PAD + 16, y + 30, 14, INK, 600);
    text(claim, PAD + 16, y + 48, 12, SUB);
    draw(y + 16 + 18 + 18);
    y += h + 12;
  };

  const trendValues = g.trend.filter((v): v is number => v !== null);
  card("Read in English", "How much of each translation stayed in English", chartH, (top) => {
    if (trendValues.length) line(PAD + 16, top, INNER - 32, chartH, g.trend, Math.max(10, Math.ceil(Math.max(...trendValues) / 5) * 5), EN, "%", true);
  });
  const saidLine = cumulative(g.said, g.days);
  const seenLine = cumulative(g.seen, g.days);
  card("Words you can say", "Words you got right in a test for the first time, added up", chartH + 18, (top) => {
    ctx.fillStyle = EN;
    ctx.fillRect(PAD + 16, top + 2, 10, 10);
    text("Said yourself", PAD + 32, top + 11, 12, SUB);
    ctx.fillStyle = SEEN;
    ctx.fillRect(PAD + 130, top + 2, 10, 10);
    text("4-Choice", PAD + 146, top + 11, 12, SUB);
    const max = Math.max(10, Math.ceil(Math.max(...saidLine, ...seenLine) / 10) * 10);
    line(PAD + 16, top + 18, INNER - 32, chartH, seenLine, max, SEEN, "", true);
    line(PAD + 16, top + 18, INNER - 32, chartH, saidLine, max, EN, "", false);
  });
  const topCount = Math.max(1, ...g.tests.flatMap(({ perDay }) => perDay));
  const rowH = 80;
  card("Tests", "Bars: times a day (right scale). Line: result that day (left scale, 0–100)", 5 * rowH, (top) => {
    g.tests.forEach(({ test, value, count, series, perDay }, row) => {
      const ry = top + row * rowH;
      text(test.label, PAD + 16, ry + 14, 13, INK, 600);
      text(value === null ? "Not yet" : `${count}× · ${formatTest(test, value)}`, PAD + INNER - 16, ry + 14, 12, SUB, 400, "right");
      const cx = PAD + 16 + 30;
      const cw = INNER - 32 - 30 - 26;
      const ct = ry + 24;
      const ch = rowH - 24 - 8;
      const step = cw / perDay.length;
      const x = (i: number) => cx + step * (i + 0.5);
      const yy = (v: number) => ct + ch - (v / 100) * ch;
      for (const gv of [0, 50, 100]) {
        ctx.fillStyle = "#e6eaee";
        ctx.fillRect(cx, yy(gv), cw, 1);
        text(`${gv}${test.unit === "%" ? "%" : ""}`, cx - 4, yy(gv) + 3, 10, SUB, 400, "right");
        text(`${Math.round((gv / 100) * topCount)}×`, cx + cw + 4, yy(gv) + 3, 10, SUB);
      }
      ctx.fillStyle = "rgba(89, 99, 110, 0.35)";
      perDay.forEach((v, i) => {
        if (!v) return;
        const h = (v / topCount) * ch;
        ctx.beginPath();
        ctx.roundRect(x(i) - step * 0.35, ct + ch - h, step * 0.7, h, 1.5);
        ctx.fill();
      });
      const points = series.flatMap((v, i) => (v === null ? [] : [[x(i), yy(v)] as const]));
      ctx.strokeStyle = EN;
      ctx.lineWidth = 2;
      ctx.beginPath();
      points.forEach(([px, py], n) => (n ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
      ctx.stroke();
      ctx.lineWidth = 1;
      ctx.fillStyle = EN;
      for (const [px, py] of points) {
        ctx.beginPath();
        ctx.arc(px, py, 3, 0, Math.PI * 2);
        ctx.fill();
      }
      if (row === 4) g.days.forEach((d, i) => (g.days.length - 1 - i) % Math.ceil(g.days.length / 5) === 0 && text(md(d), x(i), ct + ch + 14, 10, SUB, 400, "center"));
    });
  });
  card("Study days", "The days you studied, and how much. Darker means more", 110, (top) => {
    // 始めた週から今週まで。空の週ばかりが並ばないよう、最初のうちは8週だけ見せる
    const first = Math.min(...summary.allEvents.map((event) => Date.parse(event.date)), day.getTime());
    const weeks = Math.min(26, Math.max(8, Math.floor((day.getTime() - first) / (7 * 86_400_000)) + 2));
    const cell = 13;
    const gap = 3;
    const end = new Date(day.getFullYear(), day.getMonth(), day.getDate());
    const start = new Date(end);
    start.setDate(end.getDate() - end.getDay() - 7 * (weeks - 1));
    const shades = [LINE, "#c7d6ff", "#93b1ff", "#5f8bff", EN];
    for (let w = 0; w < weeks; w++) {
      for (let d = 0; d < 7; d++) {
        const date = new Date(start);
        date.setDate(start.getDate() + w * 7 + d);
        if (date > end) continue;
        const n = countOn(g.counts, date);
        ctx.fillStyle = shades[n === 0 ? 0 : n < 30 ? 1 : n < 60 ? 2 : n < 100 ? 3 : 4]!;
        ctx.beginPath();
        ctx.roundRect(PAD + 16 + w * (cell + gap), top + 4 + d * (cell + gap), cell, cell, 3);
        ctx.fill();
      }
    }
  });

  if (g.saidToday.length) {
    y += 4;
    text("Words you said today", PAD, y + 18, 17, INK, 700);
    y += 32;
    const colW = (INNER - 10) / 2;
    // 単語帳の一覧のように、英語と日本語を1行ずつ並べる。枠で囲まず、細い線で区切る
    g.saidToday.forEach((word, i) => {
      const x = PAD + (i % 2) * (colW + 10);
      const top = y + Math.floor(i / 2) * 50;
      text(word.english ?? word.term, x, top + 18, 13, INK, 600);
      text(word.japanese ?? "", x, top + 36, 11, SUB);
      ctx.fillStyle = "#eef1f4";
      ctx.fillRect(x, top + 46, colW, 1);
    });
    y += Math.ceil(g.saidToday.length / 2) * 50 + 8;
  }
  text(
    `Today: translated ${countKind(g.today, "translated")} · flipped ${countKind(g.today, "cardFlipped")} · saved ${countKind(g.today, "wordSaved")} · points ${totalPoints(g.today)}`,
    PAD,
    y + 20,
    12,
    SUB,
  );
  text("Gloss", WIDTH - PAD, y + 20, 12, EN, 700, "right");

  return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"));
}
