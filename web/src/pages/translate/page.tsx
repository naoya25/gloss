import { Fragment, type ReactNode } from "react";
import { LEVELS, phrasesOf, readingPoints, render } from "../../core/graded";
import { useTranslate } from "./store";

export function TranslatePage() {
  const { source, graded, level, translating, progress, error, read, setSource, setLevel, translate, markRead, reset } = useTranslate();
  const rendered = graded ? render(graded, level) : null;
  const phrases = graded ? phrasesOf(graded).length : 0;
  const points = rendered ? readingPoints(rendered, level) : 0;

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
          <div className="translation">
            <MixedText text={rendered.text} kept={rendered.kept} />
          </div>
          {translating && <p className="sub">Translating… {progress[0]}/{progress[1]}</p>}
          {!translating && (
            <div className="actions">
              {read ? (
                <span className="sub">Read · +{points} pt</span>
              ) : (
                <button type="button" className="primary" onClick={markRead}>
                  Done Reading +{points} pt
                </button>
              )}
            </div>
          )}
        </>
      )}
    </section>
  );
}

// 英語のまま残した語句は太字の色付きにする。押すと日本語が出る(title)
function MixedText({ text, kept }: { text: string; kept: { start: number; end: number; japanese: string; learned: boolean }[] }) {
  const pieces: ReactNode[] = [];
  let at = 0;
  kept
    .slice()
    .sort((a, b) => a.start - b.start)
    .forEach((item, i) => {
      if (item.start < at) return;
      pieces.push(<Fragment key={`t${i}`}>{text.slice(at, item.start)}</Fragment>);
      pieces.push(
        <b key={`k${i}`} className={item.learned ? "kept learned" : "kept"} title={item.japanese}>
          {text.slice(item.start, item.end)}
        </b>,
      );
      at = item.end;
    });
  pieces.push(<Fragment key="rest">{text.slice(at)}</Fragment>);
  return <>{pieces}</>;
}
