import { useState } from "react";
import { activityLabel } from "../../core/models";
import { averageScore, bookSize, countKind, dailyCounts, eventsOn, lastDays, quizTotals, streak } from "../../core/report";
import { useActivity } from "../../stores/activity";
import { useWords } from "../../stores/words";

type Tab = "today" | "progress";

export function ReportPage() {
  const [tab, setTab] = useState<Tab>("today");
  return (
    <section className="page">
      <header className="page-head">
        <h1>Report</h1>
        <div className="segmented" role="group" aria-label="View">
          {(["today", "progress"] as Tab[]).map((value) => (
            <button key={value} type="button" aria-pressed={tab === value} onClick={() => setTab(value)}>
              {value === "today" ? "Today" : "Progress"}
            </button>
          ))}
        </div>
      </header>
      {tab === "today" ? <Today /> : <Progress />}
    </section>
  );
}

function Today() {
  const events = useActivity((state) => state.events);
  const words = useWords((state) => state.words);
  const today = eventsOn(events, new Date());
  const quiz = quizTotals(today);
  const writing = averageScore(today, "writing");
  const reading = averageScore(today, "reading");
  const days = streak(events);
  const tiles: [string, string, string?][] = [
    ["Translations", `${countKind(today, "translated")}`],
    ["Words Saved", `${countKind(today, "wordSaved")}`, `${words.length} in your Book`],
    ["Cards Flipped", `${countKind(today, "cardFlipped")}`],
    ["Word Tests", quiz.total ? `${Math.round((quiz.correct * 100) / quiz.total)}%` : "–", quiz.total ? `${quiz.correct} / ${quiz.total}` : undefined],
    ["Writing", writing === null ? "–" : `${writing} pts`],
    ["Reading", reading === null ? "–" : `${reading} pts`],
  ];
  return (
    <>
      <div className="today-head">
        <span className="date">{new Date().toLocaleDateString("en-US", { month: "short", day: "numeric", weekday: "short" })}</span>
        {days > 0 && <span className="streak">🔥 {days}-day streak</span>}
      </div>
      <div className="tiles">
        {tiles.map(([label, value, caption]) => (
          <div key={label} className="tile">
            <span className="label">{label}</span>
            <strong>{value}</strong>
            <span className="sub">{caption ?? " "}</span>
          </div>
        ))}
      </div>
      {today.length === 0 ? (
        <p className="empty">Nothing yet today. Flip some cards or take a test.</p>
      ) : (
        <ul className="log">
          {today.map((event) => (
            <li key={event.id}>
              <time>{new Date(event.date).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false })}</time>
              <span className="kind">{activityLabel[event.kind]}</span>
              <span className="title">{event.title}</span>
              {event.total ? <b>{event.score}/{event.total}</b> : event.score !== undefined ? <b>{event.score} pts</b> : null}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

// 直近2週間を棒と線で見せる。グラフのライブラリは使わず、座標を計算して SVG で描く
function Progress() {
  const events = useActivity((state) => state.events);
  const words = useWords((state) => state.words);
  const days = lastDays(14);
  const counts = dailyCounts(events, days);
  const sizes = bookSize(words, days);
  return (
    <>
      <Chart title="Daily Activity" values={counts} kind="bar" days={days} />
      <Chart title="Book Size" values={sizes} kind="line" days={days} />
    </>
  );
}

function Chart({ title, values, kind, days }: { title: string; values: number[]; kind: "bar" | "line"; days: Date[] }) {
  const width = 320;
  const height = 120;
  const max = Math.max(1, ...values);
  const step = width / values.length;
  const y = (value: number) => height - (value / max) * (height - 12);
  return (
    <figure className="chart">
      <figcaption>
        {title} <span className="sub">max {max}</span>
      </figcaption>
      <svg viewBox={`0 0 ${width} ${height + 18}`} role="img" aria-label={`${title}: ${values.join(", ")}`}>
        {kind === "bar"
          ? values.map((value, i) => (
              <rect key={i} className={value ? "bar" : "bar empty"} x={i * step + 3} y={y(value)} width={step - 6} height={Math.max(2, height - y(value))} rx="3" />
            ))
          : (
              <polyline className="line" fill="none" points={values.map((value, i) => `${i * step + step / 2},${y(value)}`).join(" ")} />
            )}
        {days.map((day, i) => (i % 2 === values.length % 2 ? null : (
          <text key={i} x={i * step + step / 2} y={height + 14} textAnchor="middle">{day.getDate()}</text>
        )))}
      </svg>
    </figure>
  );
}
