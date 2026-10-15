import { Fragment, useEffect, useState } from "react";
import { LEVELS, READS_TO_RISE, nextLevel, phrasesOf, readAbility, readingPoints, render, runsOf, type Run } from "../../core/graded";
import { looksLikeMarkdown, markdownHtml } from "../../core/markdown";
import { savedRecent, useTranslate } from "./store";

export function TranslatePage() {
  const { source, graded, level, translating, progress, error, revealed, setSource, setLevel, reveal, translate, recordReading, reset } = useTranslate();
  const rendered = graded ? render(graded, level, revealed) : null;
  const phrases = graded ? phrasesOf(graded).length : 0;
  const points = rendered ? readingPoints(rendered, level) : 0;
  const ability = graded ? readAbility(graded, level, revealed) : 0;
  const next = nextLevel(level, ability, savedRecent());
  const runs = rendered ? runsOf(rendered) : [];
  const isMarkdown = !translating && rendered !== null && looksLikeMarkdown(rendered.text);
  const [showsMarkdown, setShowsMarkdown] = useState(true);

  // ページを閉じたときに、そこまで読んだ分を記録する。ほかの画面に移っただけなら記録しない
  // (記録したあとは押せなくなるので、戻ってきて続きを読めなくなる)。戻れる形で隠れたとき(persisted)も記録しない
  useEffect(() => {
    const onHide = (event: PageTransitionEvent) => {
      if (!event.persisted) recordReading();
    };
    window.addEventListener("pagehide", onHide);
    return () => window.removeEventListener("pagehide", onHide);
  }, [recordReading]);

  return (
    <section className="page translate">
      <header className="page-head">
        <h1>Translate</h1>
        {graded && (
          <button type="button" className="link" onClick={reset}>
            New
          </button>
        )}
      </header>
      {!graded && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void translate();
          }}
        >
          <textarea value={source} placeholder="Paste English here" rows={8} onChange={(event) => setSource(event.target.value)} />
          <div className="actions">
            <button type="submit" className="primary" disabled={!source.trim() || translating}>
              {translating ? `Translating… ${progress[0]}/${progress[1]}` : "Translate"}
            </button>
          </div>
        </form>
      )}
      {error && <p className="error">{error}</p>}
      {graded && rendered && (
        <>
          {level !== 0 && <p className="level-hint">Tap English you don't know to see it in Japanese</p>}
          <div className="segmented levels" role="group" aria-label="English in the translation">
            {LEVELS.map((item) => (
              <button key={item.level} type="button" aria-pressed={level === item.level} onClick={() => setLevel(item.level)}>
                {item.label}
              </button>
            ))}
          </div>
          <p className="sub level-note">
            {level === 90
              ? `The original English, with Japanese for the hardest phrases · ${rendered.englishRate}% of the text in English`
              : level === 0
                ? "Everything in Japanese"
                : `${new Set(rendered.kept.map((item) => item.english.toLowerCase())).size} of ${phrases} phrases in English · ${rendered.englishRate}% of the text`}
          </p>
          {isMarkdown && (
            <label className="markdown-toggle">
              <input type="checkbox" checked={showsMarkdown} onChange={(event) => setShowsMarkdown(event.target.checked)} /> Markdown
            </label>
          )}
          {isMarkdown && showsMarkdown ? (
            <MarkdownText runs={runs} onReveal={reveal} />
          ) : (
            <div className="translation">
              <MixedText runs={runs} onReveal={reveal} />
            </div>
          )}
          {translating && <p className="sub">Translating… {progress[0]}/{progress[1]}</p>}
          {!translating && (
            <p className="sub">
              Read {ability}% in English · next text at {LEVELS.find((item) => item.level === next.level)!.label}
              {next.level === level && level !== 90 && ` (${next.recent.length}/${READS_TO_RISE} to move up)`} · +{points} pt
            </p>
          )}
        </>
      )}
    </section>
  );
}

// 英語のまま残した語句は太字の色付きにする(90% では ✓ の語だけ)。押すと日本語になり、押した分だけ次の段階が下がる。
// 押した数で段階を決めるので、title で日本語を出さない
function MixedText({ runs, onReveal }: { runs: Run[]; onReveal: (english: string) => void }) {
  return runs.map((run, i) =>
    run.item ? (
      <button key={i} type="button" className={run.kind === "kept" ? (run.item.learned ? "kept learned" : "kept") : run.kind} onClick={() => onReveal(run.item!.english)}>
        {run.text}
      </button>
    ) : (
      <Fragment key={i}>{run.text}</Fragment>
    ),
  );
}

// 押せる語句は data-run の番号で runs から引く。HTML は markdown-it が html: false で作るので、入力の HTML タグは文字のまま出る
function MarkdownText({ runs, onReveal }: { runs: Run[]; onReveal: (english: string) => void }) {
  return (
    <div
      className="translation markdown"
      onClick={(event) => {
        const index = (event.target as HTMLElement).closest("button[data-run]")?.getAttribute("data-run");
        const item = index ? runs[Number(index)]?.item : undefined;
        if (item) onReveal(item.english);
      }}
      dangerouslySetInnerHTML={{ __html: markdownHtml(runs) }}
    />
  );
}
