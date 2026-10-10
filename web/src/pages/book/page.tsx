import { useEffect, useMemo } from "react";
import { Mastery, hasCardPair, masteryLabel, type WordEntry } from "../../core/models";
import { useActivity } from "../../stores/activity";
import { useWords } from "../../stores/words";
import { MasteryMark } from "../../widgets/mastery";
import { sortLabels, useBook, type Face, type Sort } from "./store";

export function BookPage() {
  const words = useWords((state) => state.words);
  const loaded = useWords((state) => state.loaded);
  const { face, sort, order, setFace, setSort, refresh } = useBook();

  useEffect(() => {
    if (loaded) refresh(useWords.getState().words);
  }, [loaded, refresh]);

  const ordered = useMemo(() => {
    const byID = new Map(words.map((word) => [word.id, word]));
    const known = new Set(order);
    return [...words.filter((word) => !known.has(word.id)), ...order.map((id) => byID.get(id)).filter((word): word is WordEntry => !!word)];
  }, [words, order]);

  return (
    <section className="page">
      <header className="page-head">
        <h1>
          Book <span className="count">{words.length}</span>
        </h1>
        <div className="controls">
          <div className="segmented" role="group" aria-label="Front side">
            {(["english", "japanese"] as Face[]).map((value) => (
              <button key={value} type="button" aria-pressed={face === value} onClick={() => setFace(value)}>
                {value === "english" ? "EN" : "JA"}
              </button>
            ))}
          </div>
          <select aria-label="Sort" value={sort} onChange={(event) => setSort(event.target.value as Sort, words)}>
            {(Object.keys(sortLabels) as Sort[]).map((value) => (
              <option key={value} value={value}>
                {sortLabels[value]}
              </option>
            ))}
          </select>
        </div>
      </header>
      {!loaded ? null : words.length === 0 ? (
        <p className="empty">Your Book is empty. Words you save on the Mac show up here.</p>
      ) : (
        <ul className="cards">
          {ordered.map((word) => (
            <WordCard key={word.id} word={word} face={face} />
          ))}
        </ul>
      )}
    </section>
  );
}

function WordCard({ word, face }: { word: WordEntry; face: Face }) {
  const isOpen = useBook((state) => state.openID === word.id);
  const toggle = useBook((state) => state.toggle);
  const recordFlip = useWords((state) => state.recordFlip);
  const setMastery = useWords((state) => state.setMastery);
  const record = useActivity((state) => state.record);

  const front = hasCardPair(word) ? (face === "english" ? word.english! : word.japanese!) : word.term;
  const back = hasCardPair(word) ? (face === "english" ? word.japanese! : word.english!) : word.term;

  function flip() {
    if (toggle(word.id)) {
      recordFlip(word.id);
      record({ kind: "cardFlipped", title: word.term, wordID: word.id });
    }
  }

  return (
    <li className={`card${isOpen ? " open" : ""}`}>
      <button type="button" className="card-face" aria-expanded={isOpen} onClick={flip}>
        <span className="card-text" key={isOpen ? "back" : "front"}>
          {isOpen ? back : front}
        </span>
        <span className="card-meta">
          <MasteryMark mastery={word.mastery ?? Mastery.NotYet} />
          {word.flips ?? 0}
        </span>
      </button>
      {isOpen && (
        <div className="card-back">
          {word.example && (
            <p>
              <span className="label">Example</span>
              {word.example}
              {word.exampleTranslation && <span className="sub">{word.exampleTranslation}</span>}
            </p>
          )}
          {word.note && (
            <p className="note">
              <span className="label">Note</span>
              {word.note}
            </p>
          )}
          <div className="mastery" role="group" aria-label="Mastery">
            {[Mastery.NotYet, Mastery.Unsure, Mastery.Known].map((level) => (
              <button
                key={level}
                type="button"
                data-level={level}
                aria-pressed={(word.mastery ?? -1) === level}
                onClick={() => setMastery(word.id, level)}
              >
                <MasteryMark mastery={level} /> {masteryLabel[level]}
              </button>
            ))}
          </div>
        </div>
      )}
    </li>
  );
}
