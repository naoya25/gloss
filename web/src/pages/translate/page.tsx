import { Fragment, useEffect, type ReactNode } from "react";
import { LEVELS, READS_TO_RISE, nextLevel, phrasesOf, readAbility, readingPoints, render, type Kept } from "../../core/graded";
import { savedRecent, useTranslate } from "./store";

export function TranslatePage() {
  const { source, graded, level, translating, progress, error, revealed, setSource, setLevel, reveal, translate, recordReading, reset } = useTranslate();
  const rendered = graded ? render(graded, level, revealed) : null;
  const phrases = graded ? phrasesOf(graded).length : 0;
  const points = rendered ? readingPoints(rendered, level) : 0;
  const ability = graded ? readAbility(graded, level, revealed) : 0;
  const next = nextLevel(level, ability, savedRecent());

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
          <div className="translation">
            <MixedText text={rendered.text} kept={rendered.kept} clickable={[...rendered.clickable, ...rendered.revealed]} revealed={rendered.revealed} onReveal={reveal} />
          </div>
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
function MixedText({ text, kept, clickable, revealed, onReveal }: { text: string; kept: Kept[]; clickable: Kept[]; revealed: Kept[]; onReveal: (english: string) => void }) {
  const colored = new Set(kept.map((item) => item.start));
  const back = new Set(revealed.map((item) => item.start));
  const pieces: ReactNode[] = [];
  let at = 0;
  clickable
    .slice()
    .sort((a, b) => a.start - b.start)
    .forEach((item, i) => {
      if (item.start < at) return;
      pieces.push(<Fragment key={`t${i}`}>{text.slice(at, item.start)}</Fragment>);
      pieces.push(
        <button key={`k${i}`} type="button" className={back.has(item.start) ? "revealed" : !colored.has(item.start) ? "phrase" : item.learned ? "kept learned" : "kept"} onClick={() => onReveal(item.english)}>
          {text.slice(item.start, item.end)}
        </button>,
      );
      at = item.end;
    });
  pieces.push(<Fragment key="rest">{text.slice(at)}</Fragment>);
  return <>{pieces}</>;
}
