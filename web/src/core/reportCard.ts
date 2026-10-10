import type { ActivityEvent } from "./models";
import { averageScore, countKind, quizTotals } from "./report";

export interface ReportSummary {
  day: Date;
  streak: number;
  events: ActivityEvent[];
}

const dateLabel = (day: Date) => day.toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", weekday: "short" });

// Mac の DayReport.markdown と同じ中身
export function reportMarkdown({ day, events }: ReportSummary): string {
  const quiz = quizTotals(events);
  const writing = averageScore(events, "writing");
  const reading = averageScore(events, "reading");
  const lines = [`# Study Report: ${dateLabel(day)}`, ""];
  lines.push(`- Translations: ${countKind(events, "translated")}`);
  lines.push(`- Words saved: ${countKind(events, "wordSaved")}`);
  lines.push(`- Cards flipped: ${countKind(events, "cardFlipped")}`);
  if (quiz.total > 0) lines.push(`- Word Test: ${quiz.correct} / ${quiz.total} correct`);
  if (writing !== null) lines.push(`- Writing Test: ${countKind(events, "writing")} tasks, average ${writing} pts`);
  if (reading !== null) lines.push(`- Reading Test: ${countKind(events, "reading")} tasks, average ${reading} pts`);
  const saved = events.filter((event) => event.kind === "wordSaved").map((event) => event.title).reverse();
  if (saved.length) lines.push("", "## Words Saved", "", ...saved.map((title) => `- ${title}`));
  const writings = events.filter((event) => event.kind === "writing").reverse();
  if (writings.length) {
    lines.push("", "## Writing Test", "");
    for (const event of writings) {
      lines.push(`- ${event.title} (${event.score ?? 0} pts)`);
      if (event.detail) lines.push(`  - ${event.detail}`);
    }
  }
  return lines.join("\n");
}

const INK = "#1f2328";
const SUB = "#59636e";
const LINE = "#d1d9e0";
const TILE = "#f6f8fa";
const ACCENT = "#2f6bff";
const FONT = '-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", sans-serif';
const WIDTH = 640;
const PAD = 32;

// Mac の ReportShareCard と同じ並びの画像を描く。貼り先の地の色が分からないので、白地に決め打ち
export async function reportImage(summary: ReportSummary): Promise<Blob> {
  const { day, streak, events } = summary;
  const quiz = quizTotals(events);
  const writing = averageScore(events, "writing");
  const reading = averageScore(events, "reading");
  const tiles: [string, string][] = [
    ["Translations", `${countKind(events, "translated")}`],
    ["Words Saved", `${countKind(events, "wordSaved")}`],
    ["Cards Flipped", `${countKind(events, "cardFlipped")}`],
    ["Word Tests", quiz.total ? `${quiz.correct}/${quiz.total}` : "–"],
    ["Writing", writing === null ? "–" : `${writing} pts`],
    ["Reading", reading === null ? "–" : `${reading} pts`],
  ];
  const saved = events.filter((event) => event.kind === "wordSaved").map((event) => event.title).reverse();
  const writings = events.filter((event) => event.kind === "writing").reverse();

  const scale = 2;
  const measure = document.createElement("canvas").getContext("2d")!;
  const font = (size: number, weight = 400) => `${weight} ${size}px ${FONT}`;

  // 先に高さを決めるため、単語の並びと英作の行の折り返しを計算する
  measure.font = font(13, 500);
  const chips: { x: number; y: number; w: number; text: string }[] = [];
  let cx = 0;
  let cy = 0;
  for (const text of saved) {
    const w = measure.measureText(text).width + 20;
    if (cx > 0 && cx + w > WIDTH - PAD * 2) {
      cx = 0;
      cy += 30;
    }
    chips.push({ x: cx, y: cy, w, text });
    cx += w + 6;
  }
  const wrap = (text: string, size: number, width: number) => {
    measure.font = font(size);
    const out: string[] = [];
    let line = "";
    for (const char of text) {
      if (measure.measureText(line + char).width > width && line) {
        out.push(line);
        line = char;
      } else line += char;
    }
    if (line) out.push(line);
    return out;
  };
  const writingRows = writings.map((event) => ({
    title: wrap(event.title, 13, WIDTH - PAD * 2 - 70),
    detail: event.detail ? wrap(event.detail, 12, WIDTH - PAD * 2 - 70) : [],
    score: `${event.score ?? 0} pts`,
  }));

  let height = PAD + 58 + 22 + 2 * 74 + 10;
  if (saved.length) height += 22 + 24 + cy + 26;
  if (writings.length) height += 22 + 24 + writingRows.reduce((sum, row) => sum + row.title.length * 18 + row.detail.length * 17 + 10, 0);
  height += 22 + 14 + PAD;

  const canvas = document.createElement("canvas");
  canvas.width = WIDTH * scale;
  canvas.height = height * scale;
  const ctx = canvas.getContext("2d")!;
  ctx.scale(scale, scale);
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, WIDTH, height);
  ctx.textBaseline = "alphabetic";

  let y = PAD;
  ctx.fillStyle = ACCENT;
  ctx.font = font(13, 600);
  ctx.fillText("Study Report", PAD, y + 13);
  ctx.fillStyle = INK;
  ctx.font = font(26, 700);
  ctx.fillText(dateLabel(day), PAD, y + 48);
  if (streak > 0) {
    ctx.font = font(14, 600);
    ctx.fillStyle = "#bf8700";
    ctx.textAlign = "right";
    ctx.fillText(`🔥 ${streak}-day streak`, WIDTH - PAD, y + 46);
    ctx.textAlign = "left";
  }
  y += 58 + 22;

  const tileW = (WIDTH - PAD * 2 - 20) / 3;
  tiles.forEach(([label, value], i) => {
    const x = PAD + (i % 3) * (tileW + 10);
    const ty = y + Math.floor(i / 3) * 74;
    ctx.fillStyle = TILE;
    ctx.strokeStyle = LINE;
    ctx.beginPath();
    ctx.roundRect(x + 0.5, ty + 0.5, tileW - 1, 63, 10);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = SUB;
    ctx.font = font(11, 500);
    ctx.fillText(label, x + 14, ty + 24);
    ctx.fillStyle = INK;
    ctx.font = font(24, 700);
    ctx.fillText(value, x + 14, ty + 52);
  });
  y += 2 * 74 + 10;

  const section = (title: string) => {
    y += 22;
    ctx.fillStyle = SUB;
    ctx.font = font(12, 600);
    ctx.fillText(title, PAD, y + 12);
    y += 24;
  };
  if (saved.length) {
    section("Words Saved");
    for (const chip of chips) {
      ctx.fillStyle = "rgba(47, 107, 255, 0.1)";
      ctx.beginPath();
      ctx.roundRect(PAD + chip.x, y + chip.y, chip.w, 24, 12);
      ctx.fill();
      ctx.fillStyle = INK;
      ctx.font = font(13, 500);
      ctx.fillText(chip.text, PAD + chip.x + 10, y + chip.y + 17);
    }
    y += cy + 26;
  }
  if (writings.length) {
    section("Writing Test");
    for (const row of writingRows) {
      ctx.textAlign = "right";
      ctx.fillStyle = INK;
      ctx.font = font(13, 600);
      ctx.fillText(row.score, WIDTH - PAD, y + 13);
      ctx.textAlign = "left";
      ctx.font = font(13);
      for (const line of row.title) {
        ctx.fillText(line, PAD, y + 13);
        y += 18;
      }
      ctx.fillStyle = SUB;
      ctx.font = font(12);
      for (const line of row.detail) {
        ctx.fillText(line, PAD, y + 12);
        y += 17;
      }
      y += 10;
    }
  }
  y += 22;
  ctx.fillStyle = SUB;
  ctx.font = font(11, 600);
  ctx.fillText("Gloss", PAD, y + 11);

  return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"));
}
