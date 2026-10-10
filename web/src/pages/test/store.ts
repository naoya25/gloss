import { create } from "zustand";
import { Mastery, expectedFor, promptFor, type Direction, type WordEntry } from "../../core/models";
import { isExactAnswer, pickQuestions, type Grade } from "../../core/quiz";
import { useActivity } from "../../stores/activity";
import { currentApi } from "../../stores/sync";
import { useWords } from "../../stores/words";

interface Quiz {
  questions: WordEntry[];
  answers: Record<string, string>;
  grades: Record<string, Grade>;
  grading: boolean;
  error: string | null;
}

const emptyQuiz = (): Quiz => ({ questions: [], answers: {}, grades: {}, grading: false, error: null });

interface TestState {
  direction: Direction;
  quizzes: Record<Direction, Quiz>;
  setDirection: (direction: Direction) => void;
  open: () => void;
  start: (onlyMissed?: boolean) => void;
  setAnswer: (id: string, answer: string) => void;
  grade: () => Promise<void>;
  setVerdict: (id: string, verdict: Mastery) => void;
}

export const isGraded = (quiz: Quiz) =>
  quiz.questions.length > 0 && quiz.questions.every((word) => quiz.grades[word.id] && !quiz.grades[word.id]!.pending);

export const useTest = create<TestState>()((setState, getState) => {
  function update(patch: (quiz: Quiz) => Quiz) {
    const { direction, quizzes } = getState();
    setState({ quizzes: { ...quizzes, [direction]: patch(quizzes[direction]) } });
  }
  const current = () => getState().quizzes[getState().direction];

  // 全問の採点が決まったら、Book の度合いに入れて記録を残す
  function finish() {
    const quiz = current();
    if (!isGraded(quiz)) return;
    const direction = getState().direction;
    const words = useWords.getState();
    for (const word of quiz.questions) words.recordQuizAnswer(word.id, quiz.grades[word.id]!.verdict);
    const kind = direction === "toEnglish" ? "wordQuiz" : "meaningQuiz";
    useActivity.getState().record({
      kind,
      title: kind === "wordQuiz" ? "Word Test" : "Meaning Test",
      score: quiz.questions.filter((word) => quiz.grades[word.id]!.verdict === Mastery.Known).length,
      total: quiz.questions.length,
      answers: quiz.questions.map((word) => ({
        wordID: word.id,
        prompt: promptFor(word, direction),
        answer: quiz.answers[word.id] ?? "",
        verdict: quiz.grades[word.id]!.verdict,
      })),
    });
  }

  return {
    direction: "toEnglish",
    quizzes: { toEnglish: emptyQuiz(), toJapanese: emptyQuiz() },
    setDirection: (direction) => {
      setState({ direction });
      getState().open();
    },
    open() {
      if (current().questions.length === 0) getState().start();
    },
    start(onlyMissed = false) {
      const quiz = current();
      const words = useWords.getState().words;
      const questions = onlyMissed
        ? quiz.questions.filter((word) => quiz.grades[word.id]?.verdict !== Mastery.Known).map((word) => words.find((w) => w.id === word.id) ?? word)
        : pickQuestions(words);
      update(() => ({ ...emptyQuiz(), questions }));
    },
    setAnswer: (id, answer) => update((quiz) => ({ ...quiz, answers: { ...quiz.answers, [id]: answer } })),
    // 答えと同じものはその場で正解にして、残りだけ Worker 経由で AI に採点してもらう
    async grade() {
      const quiz = current();
      if (quiz.grading || isGraded(quiz)) return;
      const direction = getState().direction;
      const grades: Record<string, Grade> = {};
      const items: { number: number; prompt: string; expected: string; answer: string; id: string }[] = [];
      quiz.questions.forEach((word, index) => {
        const answer = (quiz.answers[word.id] ?? "").trim();
        if (!answer) grades[word.id] = { verdict: Mastery.NotYet, comment: "" };
        else if (isExactAnswer(answer, word, direction)) grades[word.id] = { verdict: Mastery.Known, comment: "" };
        else items.push({ number: index + 1, prompt: promptFor(word, direction), expected: expectedFor(word, direction), answer: answer.slice(0, 200), id: word.id });
      });
      if (items.length) {
        update((q) => ({ ...q, grading: true, error: null }));
        try {
          const api = currentApi();
          if (!api) throw new Error("Not signed in");
          const reviewed = await api.gradeWordTest(direction, items.map(({ id: _id, ...item }) => item));
          for (const item of items) {
            const result = reviewed[String(item.number)];
            grades[item.id] = result
              ? { verdict: result.verdict as Mastery, comment: result.comment }
              : { verdict: Mastery.NotYet, comment: "", pending: true };
          }
        } catch {
          // AI に届かなかった問題は、正解を見せて自分で付けてもらう
          for (const item of items) grades[item.id] = { verdict: Mastery.NotYet, comment: "", pending: true };
          update((q) => ({ ...q, error: "Couldn't reach the AI. Mark these yourself." }));
        }
      }
      update((q) => ({ ...q, grades, grading: false }));
      finish();
    },
    // 判定を変える。自分で付ける問題が全部決まったら、その時点で記録する
    setVerdict(id, verdict) {
      const wasGraded = isGraded(current());
      update((quiz) => ({ ...quiz, grades: { ...quiz.grades, [id]: { ...quiz.grades[id]!, verdict, pending: false } } }));
      if (wasGraded) useWords.getState().setMastery(id, verdict);
      else finish();
    },
  };
});
