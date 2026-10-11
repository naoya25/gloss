import { useEffect } from "react";
import { Mastery, expectedFor, promptFor, type Direction, type WordEntry } from "../../core/models";
import { useWords } from "../../stores/words";
import { MasteryMark } from "../../widgets/mastery";
import { correctCount, isCorrect, isFinished, useChoice, type ChoiceQuiz } from "./store";

export function ChoicePage() {
  const loaded = useWords((state) => state.loaded);
  const quizzable = useWords((state) => state.words.filter((word) => word.english && word.japanese).length);
  const { direction, quizzes, setDirection, open } = useChoice();
  const quiz = quizzes[direction];
  const word = quiz.questions[quiz.index];

  useEffect(() => {
    if (loaded) open();
  }, [loaded, open]);

  if (loaded && quizzable === 0) return <p className="empty page">No words to test yet.</p>;

  return (
    <section className="page">
      <header className="page-head">
        <h1>4-Choice Test</h1>
        <div className="segmented" role="group" aria-label="Direction">
          {(["toEnglish", "toJapanese"] as Direction[]).map((value) => (
            <button key={value} type="button" aria-pressed={direction === value} onClick={() => setDirection(value)}>
              {value === "toEnglish" ? "JA → EN" : "EN → JA"}
            </button>
          ))}
        </div>
      </header>
      {isFinished(quiz) ? <Result quiz={quiz} direction={direction} /> : word && <Question key={`${quiz.round}-${quiz.index}`} quiz={quiz} word={word} direction={direction} />}
    </section>
  );
}

function Question({ quiz, word, direction }: { quiz: ChoiceQuiz; word: WordEntry; direction: Direction }) {
  const pick = useChoice((state) => state.pick);
  const next = useChoice((state) => state.next);
  const answer = expectedFor(word, direction);
  const picked = quiz.picks[word.id];

  return (
    <div className="choice">
      <div className="choice-progress">
        <span className="sub">
          {quiz.index + 1} of {quiz.questions.length}
        </span>
        <progress value={quiz.index} max={quiz.questions.length} />
      </div>
      <p className="choice-prompt">{promptFor(word, direction)}</p>
      <div className="choice-options">
        {(quiz.options[word.id] ?? []).map((option) => {
          const state = optionState(option.text, answer, picked);
          return (
            <button key={option.text} type="button" className={state} aria-disabled={picked !== undefined} onClick={() => pick(option.text)}>
              <span>
                {option.text}
                {picked !== undefined && <span className="sub">{option.meaning}</span>}
              </span>
              {state === "right" && <MasteryMark mastery={Mastery.Known} />}
              {state === "wrong" && <MasteryMark mastery={Mastery.NotYet} />}
            </button>
          );
        })}
      </div>
      {picked !== undefined && (
        <div className="actions">
          <button type="button" className="primary" onClick={() => next()}>
            Next
          </button>
        </div>
      )}
    </div>
  );
}

function Result({ quiz, direction }: { quiz: ChoiceQuiz; direction: Direction }) {
  const start = useChoice((state) => state.start);
  const correct = correctCount(quiz, direction);
  const missed = quiz.questions.length - correct;
  return (
    <>
      <div className="score">
        <strong>{correct}</strong>
        <span>/ {quiz.questions.length}</span>
        <p>Your Book moved up one step for each word you got right, and back to Not Yet for each miss.</p>
      </div>
      <ul className="choice-review">
        {quiz.questions.map((word) => {
          const right = isCorrect(quiz, word, direction);
          const answer = expectedFor(word, direction);
          const picked = quiz.picks[word.id];
          return (
            <li key={word.id}>
              <details>
                <summary>
                  <MasteryMark mastery={right ? Mastery.Known : Mastery.NotYet} />
                  <span className="prompt">{promptFor(word, direction)}</span>
                  <span>
                    {!right && <s>{picked}</s>} <b className={right ? undefined : "expected"}>{answer}</b>
                  </span>
                </summary>
                <ul className="choice-options-review">
                  {(quiz.options[word.id] ?? []).map((option) => (
                    <li key={option.text} className={optionState(option.text, answer, picked)}>
                      <b>{option.text}</b> <span className="sub">{option.meaning}</span>
                    </li>
                  ))}
                </ul>
              </details>
            </li>
          );
        })}
      </ul>
      <div className="actions">
        <button type="button" className={missed > 0 ? undefined : "primary"} onClick={() => start()}>
          New Test
        </button>
        {missed > 0 && (
          <button type="button" className="primary" onClick={() => start(true)}>
            Retry {missed} Missed
          </button>
        )}
      </div>
    </>
  );
}

function optionState(option: string, answer: string, picked: string | undefined): string {
  if (picked === undefined) return "";
  return option === answer ? "right" : option === picked ? "wrong" : "faded";
}
