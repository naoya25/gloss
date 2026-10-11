import { create } from "zustand";
import { Mastery, expectedFor, promptFor, type Direction, type WordEntry } from "../../core/models";
import { CHOICE_POINTS_PER_CORRECT, CHOICE_TITLE, choiceOptions, nextMastery, pickQuestions, type ChoiceOption } from "../../core/quiz";
import { useActivity } from "../../stores/activity";
import { useWords } from "../../stores/words";

export interface ChoiceQuiz {
  questions: WordEntry[];
  options: Record<string, ChoiceOption[]>;
  picks: Record<string, string>;
  index: number;
  // テストを始めるたびに増える番号。画面ではこれで1問ごとに作り直す
  round: number;
}

const emptyQuiz = (round = 0): ChoiceQuiz => ({ questions: [], options: {}, picks: {}, index: 0, round });

export const isFinished = (quiz: ChoiceQuiz) => quiz.questions.length > 0 && quiz.index >= quiz.questions.length;
export const isCorrect = (quiz: ChoiceQuiz, word: WordEntry, direction: Direction) => quiz.picks[word.id] === expectedFor(word, direction);
export const correctCount = (quiz: ChoiceQuiz, direction: Direction) => quiz.questions.filter((word) => isCorrect(quiz, word, direction)).length;

interface ChoiceState {
  direction: Direction;
  quizzes: Record<Direction, ChoiceQuiz>;
  setDirection: (direction: Direction) => void;
  open: () => void;
  start: (onlyMissed?: boolean) => void;
  pick: (option: string) => void;
  next: () => void;
}

export const useChoice = create<ChoiceState>()((setState, getState) => {
  function update(direction: Direction, patch: (quiz: ChoiceQuiz) => ChoiceQuiz) {
    const { quizzes } = getState();
    setState({ quizzes: { ...quizzes, [direction]: patch(quizzes[direction]) } });
  }

  function finish(quiz: ChoiceQuiz, direction: Direction) {
    const words = useWords.getState();
    for (const word of quiz.questions) {
      const current = words.words.find((w) => w.id === word.id)?.mastery ?? Mastery.NotYet;
      words.recordQuizAnswer(word.id, nextMastery(current, isCorrect(quiz, word, direction)));
    }
    const score = correctCount(quiz, direction);
    useActivity.getState().record({
      kind: direction === "toEnglish" ? "wordQuiz" : "meaningQuiz",
      title: CHOICE_TITLE,
      score,
      total: quiz.questions.length,
      points: score * CHOICE_POINTS_PER_CORRECT,
      answers: quiz.questions.map((word) => ({
        wordID: word.id,
        prompt: promptFor(word, direction),
        answer: quiz.picks[word.id] ?? "",
        verdict: isCorrect(quiz, word, direction) ? Mastery.Known : Mastery.NotYet,
      })),
    });
  }

  return {
    direction: "toEnglish",
    quizzes: { toEnglish: emptyQuiz(), toJapanese: emptyQuiz() },
    setDirection(direction) {
      setState({ direction });
      getState().open();
    },
    open() {
      const { direction, quizzes } = getState();
      if (quizzes[direction].questions.length === 0) getState().start();
    },
    start(onlyMissed = false) {
      const { direction, quizzes } = getState();
      const previous = quizzes[direction];
      const words = useWords.getState().words;
      const questions = onlyMissed
        ? previous.questions.filter((word) => !isCorrect(previous, word, direction)).map((word) => words.find((w) => w.id === word.id) ?? word)
        : pickQuestions(words, undefined, new Set(previous.questions.map((word) => word.id)));
      const options = Object.fromEntries(questions.map((word) => [word.id, choiceOptions(word, words, direction)]));
      update(direction, (quiz) => ({ ...emptyQuiz(quiz.round + 1), questions, options }));
      requestAnimationFrame(() => window.scrollTo(0, 0));
    },
    // 当たっても自動では進まない。ほかの選択肢の意味を見てから、自分で次へ進む
    pick(option) {
      const { direction, quizzes } = getState();
      const quiz = quizzes[direction];
      const word = quiz.questions[quiz.index];
      if (!word || quiz.picks[word.id] !== undefined) return;
      update(direction, (q) => ({ ...q, picks: { ...q.picks, [word.id]: option } }));
    },
    next() {
      const direction = getState().direction;
      const quiz = getState().quizzes[direction];
      const word = quiz.questions[quiz.index];
      if (!word || quiz.picks[word.id] === undefined) return;
      const advanced = { ...quiz, index: quiz.index + 1 };
      update(direction, () => advanced);
      if (isFinished(advanced)) finish(advanced, direction);
    },
  };
});
