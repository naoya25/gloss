import { useEffect } from "react";
import { Mastery, expectedFor, masteryLabel, promptFor, type Direction, type WordEntry } from "../../core/models";
import { isExactAnswer } from "../../core/quiz";
import { useWords } from "../../stores/words";
import { MasteryMark } from "../../widgets/mastery";
import { isGraded, useTest } from "./store";

export function TestPage() {
  const loaded = useWords((state) => state.loaded);
  const quizzable = useWords((state) => state.words.filter((word) => word.english && word.japanese).length);
  const { direction, quizzes, setDirection, open, start, setAnswer, grade } = useTest();
  const quiz = quizzes[direction];
  const graded = isGraded(quiz);

  useEffect(() => {
    if (loaded) open();
  }, [loaded, open]);

  if (loaded && quizzable === 0) return <p className="empty page">No words to test yet.</p>;

  const known = quiz.questions.filter((word) => quiz.grades[word.id]?.verdict === Mastery.Known).length;
  const missed = quiz.questions.length - known;

  return (
    <section className="page">
      <header className="page-head">
        <h1>{direction === "toEnglish" ? "Word Test" : "Meaning Test"}</h1>
        <div className="segmented" role="group" aria-label="Direction">
          {(["toEnglish", "toJapanese"] as Direction[]).map((value) => (
            <button key={value} type="button" aria-pressed={direction === value} onClick={() => setDirection(value)}>
              {value === "toEnglish" ? "JA → EN" : "EN → JA"}
            </button>
          ))}
        </div>
      </header>
      {graded && (
        <div className="score">
          <strong>{known}</strong>
          <span>/ {quiz.questions.length}</span>
          <p>Your Book was updated with these results.</p>
        </div>
      )}
      <form
        className="sheet"
        onSubmit={(event) => {
          event.preventDefault();
          void grade();
        }}
      >
        {quiz.questions.map((word, index) => (
          <QuestionRow
            key={word.id}
            number={index + 1}
            word={word}
            direction={direction}
            answer={quiz.answers[word.id] ?? ""}
            onAnswer={(value) => setAnswer(word.id, value)}
          />
        ))}
        {quiz.error && <p className="error">{quiz.error}</p>}
        <div className="actions">
          {graded ? (
            <>
              <button type="button" onClick={() => start()}>New Test</button>
              {missed > 0 && (
                <button type="button" className="primary" onClick={() => start(true)}>
                  Retry {missed} Missed
                </button>
              )}
            </>
          ) : (
            <button type="submit" className="primary" disabled={quiz.grading}>
              {quiz.grading ? "Checking…" : "Check All"}
            </button>
          )}
        </div>
      </form>
    </section>
  );
}

function QuestionRow(props: { number: number; word: WordEntry; direction: Direction; answer: string; onAnswer: (value: string) => void }) {
  const { number, word, direction, answer, onAnswer } = props;
  const grade = useTest((state) => state.quizzes[direction].grades[word.id]);
  const grading = useTest((state) => state.quizzes[direction].grading);
  const setVerdict = useTest((state) => state.setVerdict);
  const expected = expectedFor(word, direction);

  return (
    <div className={`question${grade && !grade.pending ? ` verdict-${grade.verdict}` : ""}`}>
      <div className="question-head">
        <span className="number">{grade && !grade.pending ? <MasteryMark mastery={grade.verdict} /> : number}</span>
        <span className="prompt">{promptFor(word, direction)}</span>
      </div>
      {!grade ? (
        <input
          type="text"
          value={answer}
          placeholder={direction === "toEnglish" ? "English" : "日本語"}
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint={number === 10 ? "done" : "next"}
          disabled={grading}
          onChange={(event) => onAnswer(event.target.value)}
        />
      ) : (
        <div className="result">
          {grade.verdict === Mastery.Known && !grade.pending ? (
            <>
              <span className="answer">{answer}</span>
              {!isExactAnswer(answer, word, direction) && <span className="sub">Book: {expected}</span>}
            </>
          ) : (
            <span className="answer">
              <s>{answer || "(blank)"}</s> → <b className="expected">{expected}</b>
            </span>
          )}
          {grade.comment && <span className="sub">{grade.comment}</span>}
          <div className="verdicts" role="group" aria-label="Change the result">
              {[Mastery.NotYet, Mastery.Unsure, Mastery.Known].map((level) => (
                <button
                  key={level}
                  type="button"
                  data-level={level}
                  aria-pressed={!grade.pending && grade.verdict === level}
                  onClick={() => setVerdict(word.id, level)}
                >
                  <MasteryMark mastery={level} /> {masteryLabel[level]}
                </button>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}
