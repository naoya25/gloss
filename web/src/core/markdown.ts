import MarkdownIt from "markdown-it";
import type { Run } from "./graded";

// 見出し・箇条書き・番号・引用・コード・表・太字・リンクのどれかがあれば Markdown として出す(Mac の MarkdownText と同じ)
export function looksLikeMarkdown(text: string): boolean {
  return /^\s{0,3}(#{1,6} |[-*+] |\d+\. |> |```|\|.*\|\s*$)/m.test(text) || /\*\*[^*\n]+\*\*|\[[^\]\n]+\]\([^)\n]+\)/.test(text);
}

const md = new MarkdownIt({ html: false, breaks: true });
const OPEN = "";
const CLOSE = "";

// 押せる語句を印に置き換えてから Markdown を HTML にし、HTML の文字の中の印を、押せる語句のボタンに戻す。
// タグの中(リンク先や alt)の印はボタンにすると HTML が壊れるので、タグの外だけを戻す
export function markdownHtml(runs: Run[]): string {
  const marked = runs.map((run, i) => (run.item ? `${OPEN}${i}${CLOSE}` : run.text)).join("");
  return md
    .render(marked)
    .split(/(<[^>]*>)/)
    .map((part) =>
      part.startsWith("<")
        ? part
        : part.replace(new RegExp(`${OPEN}(\\d+)${CLOSE}`, "g"), (_, index: string) => {
            const run = runs[Number(index)];
            if (!run?.item) return "";
            const className = run.kind === "kept" ? (run.item.learned ? "kept learned" : "kept") : run.kind;
            return `<button type="button" class="${className}" data-run="${index}">${md.utils.escapeHtml(run.text)}</button>`;
          }),
    )
    .join("");
}
