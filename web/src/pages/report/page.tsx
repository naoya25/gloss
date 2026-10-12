import { useEffect, useState, type ReactNode } from "react";
import { TEST_TRENDS, testCounts, visibleDays, cumulative, dailyCounts, countOn, distinct, englishRates, firstCorrect, formatTest, latestEnglish, matchesTest, newlyCorrect, testSeries, testValue } from "../../core/growth";
import { lessonBrief } from "../../core/lessonBrief";
import type { ActivityEvent } from "../../core/models";
import { countKind, englishRate, eventsOn, lastDays, totalPoints, streak } from "../../core/report";
import { reportImage, reportMarkdown, type ShareSummary } from "../../core/reportCard";
import { useActivity } from "../../stores/activity";
import { useWords } from "../../stores/words";

type Range = 14 | 30 | 90;
const RANGES: [Range, string][] = [
  [14, "2W"],
  [30, "1M"],
  [90, "3M"],
];

const md = (day: Date) => `${day.getMonth() + 1}/${day.getDate()}`;

// 進んでいる実感が続けるいちばんの燃料なので、やった量より先に、できるようになったことを大きく出す
export function ReportPage() {
  const events = useActivity((state) => state.events);
  const words = useWords((state) => state.words);
  const [range, setRange] = useState<Range>(14);
  const now = new Date();
  const today = eventsOn(events, now);
  const days = streak(events);
  const said = distinct(firstCorrect(events, false), words);
  const seen = distinct(firstCorrect(events, true), words);
  const latest = latestEnglish(events);
  const saidToday = newlyCorrect(said, now);
  const seenOnly = [...seen.keys()].filter((id) => !said.has(id)).length;
  const reads = today.filter((event) => event.kind === "glossRead");
  const english = reads.reduce((sum, event) => sum + (event.score ?? 0), 0);
  const translated = reads.reduce((sum, event) => sum + (event.total ?? 0), 0);
  const rate = englishRate(today);
  const rangeDays = lastDays(visibleDays(range, events, now), now);
  const recent = events.filter((event) => Date.parse(event.date) >= rangeDays[0]!.getTime());
  const byID = new Map(words.map((word) => [word.id, word]));

  return (
    <section className="page report">
      <header className="page-head">
        <h1>{now.toLocaleDateString("en-US", { month: "short", day: "numeric", weekday: "short" })}</h1>
        {days > 0 && <span className="streak">🔥 {days}-day streak</span>}
      </header>

      <div className="hero">
        <div className="hero-card">
          <span className="label">Read in English</span>
          <strong>{rate === null ? "–" : <>{rate}<small>%</small></>}</strong>
          {rate === null ? (
            <span className="sub">
              {latest
                ? `${latest.rate}% on ${md(latest.day)}, the last day you read in English. Nothing yet today.`
                : "Translate on the Mac and choose “Read It As Is” to start."}
            </span>
          ) : (
            <>
              <span className="sub">How much of today's translations stayed in English · {reads.length} texts</span>
              <div className="mixbar" aria-hidden="true">
                <span style={{ width: `${Math.max(2, (english * 100) / translated)}%` }} />
              </div>
            </>
          )}
        </div>
        <div className="hero-card">
          <span className="label">Words you can say</span>
          <strong>{said.size}</strong>
          <span className="sub">
            <b>{saidToday.length ? `+${saidToday.length} today` : "None new today"}</b> · answered yourself in tests
          </span>
          <span className="sub">Another {seenOnly} recognized in 4-Choice</span>
        </div>
      </div>

      <div className="section-head">
        <h2>Progress</h2>
        <div className="segmented" role="group" aria-label="Range">
          {RANGES.map(([value, label]) => (
            <button key={value} type="button" aria-pressed={range === value} onClick={() => setRange(value)}>
              {label}
            </button>
          ))}
        </div>
      </div>
      <Card title="Read in English" claim="How much of each translation stayed in English. The higher, the less you need translation.">
        <LineChart days={rangeDays} series={[{ name: "English", values: englishRates(events, rangeDays), className: "en" }]} unit="%" min={10} />
      </Card>
      <Card title="Words you can say" claim="Words you got right in a test for the first time, added up.">
        <div className="legend">
          <span><i className="en" />Said yourself</span>
          <span><i className="seen" />4-Choice</span>
        </div>
        <LineChart
          days={rangeDays}
          series={[
            { name: "Said", values: cumulative(said, rangeDays), className: "en" },
            { name: "4-Choice", values: cumulative(seen, rangeDays), className: "seen" },
          ]}
          unit=""
          min={10}
        />
      </Card>
      <Card title="Tests" claim="Bars: times a day. Line: how you did that day (share correct for word tests, average score for Writing and Reading).">
        <TestsChart events={events} recent={recent} days={rangeDays} />
      </Card>
      <Card title="Study days" claim="The days you studied, and how much. Darker means more.">
        <StudyCalendar counts={dailyCounts(events)} today={now} weeks={calendarWeeks(events, now)} />
      </Card>

      <h2>Words you said today</h2>
      <p className="sub">Words you got right for the first time in a Word or Meaning Test.</p>
      {saidToday.length ? (
        <ul className="said">
          {saidToday.map((id) => {
            const word = byID.get(id);
            return word ? (
              <li key={id}>
                <b>{word.english ?? word.term}</b>
                <span className="sub">{word.japanese}</span>
              </li>
            ) : null;
          })}
        </ul>
      ) : (
        <p className="empty">Take a Word or Meaning Test, and the words you get right show up here.</p>
      )}

      <p className="today-counts">
        Today: translated <b>{countKind(today, "translated")}</b> · flipped <b>{countKind(today, "cardFlipped")}</b> · saved{" "}
        <b>{countKind(today, "wordSaved")}</b> · points <b>{totalPoints(today)}</b> <span className="sub">({totalPoints(events)} in total)</span>
      </p>

      <ShareReport summary={{ day: now, streak: days, allEvents: events, words }} hasToday={today.length > 0} />
      <CopyLesson />
    </section>
  );
}

function Card({ title, claim, children }: { title: string; claim: string; children: ReactNode }) {
  return (
    <figure className="chart">
      <figcaption>
        {title}
        <span className="sub">{claim}</span>
      </figcaption>
      {children}
    </figure>
  );
}

interface Series {
  name: string;
  values: (number | null)[];
  className: string;
}

// グラフのライブラリは使わず、座標を計算して SVG で描く。押した日の値を上に出す
function LineChart({ days, series, unit, min }: { days: Date[]; series: Series[]; unit: string; min: number }) {
  const [picked, setPicked] = useState<number | null>(null);
  const width = 320;
  const height = 130;
  const pad = { l: 28, r: 8, t: 10, b: 18 };
  const all = series.flatMap((s) => s.values.filter((v): v is number => v !== null));
  if (!all.length) return <p className="empty">Nothing in this range yet.</p>;
  const max = Math.max(min, Math.ceil(Math.max(...all) / 5) * 5);
  const x = (i: number) => pad.l + (i * (width - pad.l - pad.r)) / Math.max(1, days.length - 1);
  const y = (v: number) => height - pad.b - (v / max) * (height - pad.t - pad.b);
  const step = Math.ceil(days.length / 5);
  return (
    <>
      <p className="chart-tip">
        {picked === null
          ? "Tap the chart to see a day"
          : `${md(days[picked]!)} · ${series.map((s) => `${s.name} ${s.values[picked] === null ? "–" : Math.round(s.values[picked]!) + unit}`).join(" · ")}`}
      </p>
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={series.map((s) => s.name).join(", ")}>
        {[0, max / 2, max].map((g) => (
          <g key={g}>
            <line className="grid" x1={pad.l} x2={width - pad.r} y1={y(g)} y2={y(g)} />
            <text x={pad.l - 4} y={y(g) + 3} textAnchor="end">
              {Math.round(g)}
              {unit}
            </text>
          </g>
        ))}
        {series.map((s) => {
          const points = s.values.flatMap((v, i) => (v === null ? [] : [`${x(i)},${y(v)}`]));
          return (
            <g key={s.name} className={s.className}>
              <polyline className="line" fill="none" points={points.join(" ")} />
              {s.values.map((v, i) => (v === null ? null : <circle key={i} cx={x(i)} cy={y(v)} r={i === picked ? 4.5 : 2.5} />))}
            </g>
          );
        })}
        {picked !== null && <line className="rule" x1={x(picked)} x2={x(picked)} y1={pad.t} y2={height - pad.b} />}
        {days.map((day, i) => (
          <g key={i}>
            {(days.length - 1 - i) % step === 0 && (
              <text x={x(i)} y={height - 4} textAnchor="middle">
                {md(day)}
              </text>
            )}
            <rect
              x={x(i) - (width - pad.l - pad.r) / days.length / 2}
              y={pad.t}
              width={(width - pad.l - pad.r) / days.length}
              height={height - pad.t - pad.b}
              fill="transparent"
              onClick={() => setPicked(i)}
              onMouseEnter={() => setPicked(i)}
            />
          </g>
        ))}
      </svg>
    </>
  );
}

// テストごとに1つのグラフ。棒がその日にやった回数(右の目盛り)、線がその日の成績(左の目盛り、0〜100)。
// 回数は 0〜top を同じ枠の高さに縮めて描く。どのテストも同じ top にして、回数を比べられるようにする
function TestsChart({ events, recent, days }: { events: ActivityEvent[]; recent: ActivityEvent[]; days: Date[] }) {
  const counts = TEST_TRENDS.map((test) => testCounts(test, events, days));
  const top = Math.max(1, ...counts.flat());
  return (
    <div className="tests">
      {TEST_TRENDS.map((test, i) => {
        const value = testValue(test, recent);
        const count = recent.filter((event) => matchesTest(test, event)).length;
        return (
          <div key={test.id} className="tests-row">
            <div className="tests-title">
              <b>{test.label}</b>
              <span className="sub">{value === null ? "Not yet" : `${count}× · ${formatTest(test, value)}`}</span>
            </div>
            {/* 日付の目盛りは一番下の行だけに書く。5行とも同じ日付なので */}
            <ComboChart days={days} counts={counts[i]!} results={testSeries(test, events, days)} top={top} unit={test.unit === "%" ? "%" : ""} showsDates={i === TEST_TRENDS.length - 1} />
          </div>
        );
      })}
    </div>
  );
}

function ComboChart(props: { days: Date[]; counts: number[]; results: (number | null)[]; top: number; unit: string; showsDates: boolean }) {
  const { days, counts, results, top, unit, showsDates } = props;
  const [picked, setPicked] = useState<number | null>(null);
  const width = 320;
  const height = showsDates ? 92 : 74;
  const pad = { l: 30, r: 26, t: 8, b: showsDates ? 18 : 4 };
  const inner = width - pad.l - pad.r;
  const step = inner / days.length;
  const x = (i: number) => pad.l + step * (i + 0.5);
  const y = (v: number) => height - pad.b - (v / 100) * (height - pad.t - pad.b);
  const points = results.flatMap((v, i) => (v === null ? [] : [[x(i), y(v)] as const]));
  const every = Math.ceil(days.length / 5);
  return (
    <>
      <p className="chart-tip">
        {picked === null
          ? " "
          : `${md(days[picked]!)} · ${counts[picked]}× · ${results[picked] === null ? "–" : Math.round(results[picked]!) + (unit || " pts")}`}
      </p>
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Times a day and results">
        {[0, 50, 100].map((g) => (
          <g key={g}>
            <line className="grid" x1={pad.l} x2={width - pad.r} y1={y(g)} y2={y(g)} />
            <text x={pad.l - 4} y={y(g) + 3} textAnchor="end">
              {g}
              {unit}
            </text>
            <text className="faint" x={width - pad.r + 4} y={y(g) + 3}>
              {Math.round((g / 100) * top)}×
            </text>
          </g>
        ))}
        {counts.map((v, i) =>
          v === 0 ? null : <rect key={i} className="test-bar" x={x(i) - step * 0.35} y={y((v / top) * 100)} width={step * 0.7} height={y(0) - y((v / top) * 100)} rx={1.5} />,
        )}
        <polyline className="line en-stroke" fill="none" points={points.map((p) => p.join(",")).join(" ")} />
        {points.map(([px, py], i) => (
          <circle key={i} className="en-dot" cx={px} cy={py} r={3} />
        ))}
        {days.map((day, i) => (
          <g key={i}>
            {showsDates && (days.length - 1 - i) % every === 0 && (
              <text x={x(i)} y={height - 4} textAnchor="middle">
                {md(day)}
              </text>
            )}
            <rect x={x(i) - step / 2} y={pad.t} width={step} height={height - pad.t - pad.b} fill="transparent" onClick={() => setPicked(i)} onMouseEnter={() => setPicked(i)} />
          </g>
        ))}
      </svg>
    </>
  );
}

// やった日のカレンダー。列が週、行が曜日。濃さは記録の数を5段にしたもの
// 始めた週から今週まで。空の週ばかりが並ばないよう、最初のうちは8週だけ見せ、多くても15週まで
function calendarWeeks(events: { date: string }[], today: Date): number {
  if (!events.length) return 8;
  const first = Math.min(...events.map((event) => Date.parse(event.date)));
  return Math.min(15, Math.max(8, Math.floor((today.getTime() - first) / (7 * 86_400_000)) + 2));
}

function StudyCalendar({ counts, today, weeks }: { counts: Map<string, number>; today: Date; weeks: number }) {
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const start = new Date(end);
  start.setDate(end.getDate() - end.getDay() - 7 * (weeks - 1));
  const level = (n: number) => (n === 0 ? 0 : n < 30 ? 1 : n < 60 ? 2 : n < 100 ? 3 : 4);
  return (
    <>
      <div className="calendar" style={{ gridTemplateColumns: `repeat(${weeks}, minmax(0, 20px))` }}>
        {Array.from({ length: weeks }, (_, week) => (
          <div key={week}>
            {Array.from({ length: 7 }, (_, weekday) => {
              const day = new Date(start);
              day.setDate(start.getDate() + week * 7 + weekday);
              if (day > end) return <i key={weekday} className="future" />;
              const n = countOn(counts, day);
              return <i key={weekday} className={`level-${level(n)}`} title={`${md(day)}: ${n ? `${n} records` : "no study"}`} />;
            })}
          </div>
        ))}
      </div>
      <div className="calendar-legend">
        Less <i className="level-0" /><i className="level-1" /><i className="level-2" /><i className="level-3" /><i className="level-4" /> More
      </div>
    </>
  );
}

// 画像は開いたときに作っておく。押してから作ると、iPhone の Safari が共有を「操作の直後ではない」として断るため
function ShareReport({ summary, hasToday }: { summary: ShareSummary; hasToday: boolean }) {
  const [image, setImage] = useState<Blob | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const key = `${summary.allEvents.length}-${summary.words.length}`;

  useEffect(() => {
    if (!hasToday) return;
    let alive = true;
    void reportImage(summary).then((blob) => alive && setImage(blob));
    return () => {
      alive = false;
    };
    // 記録か単語が増えたときだけ描き直す
  }, [key, summary.streak, hasToday]);

  if (!hasToday) return null;

  function flash(text: string) {
    setStatus(text);
    setTimeout(() => setStatus(null), 1800);
  }

  async function shareImage() {
    if (!image) return;
    const file = new File([image], `gloss-report-${summary.day.toISOString().slice(0, 10)}.png`, { type: "image/png" });
    try {
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file] });
      } else if ("ClipboardItem" in window) {
        await navigator.clipboard.write([new ClipboardItem({ "image/png": image })]);
        flash("Copied");
      } else {
        const link = document.createElement("a");
        link.href = URL.createObjectURL(file);
        link.download = file.name;
        link.click();
        URL.revokeObjectURL(link.href);
      }
    } catch (error) {
      if ((error as Error).name !== "AbortError") flash("Couldn't share");
    }
  }

  async function copyText() {
    try {
      await navigator.clipboard.writeText(reportMarkdown(summary));
      flash("Copied");
    } catch {
      flash("Couldn't copy");
    }
  }

  return (
    <div className="share">
      <button type="button" className="primary" disabled={!image} onClick={() => void shareImage()}>
        Share Image
      </button>
      <button type="button" onClick={() => void copyText()}>
        Copy as Markdown
      </button>
      {status && <span className="sub">{status}</span>}
    </div>
  );
}

// 単語帳と最近のテストを全部まとめてコピーする。ChatGPT の音声通話に貼ってレッスンしてもらう用
function CopyLesson() {
  const events = useActivity((state) => state.events);
  const words = useWords((state) => state.words);
  const [status, setStatus] = useState<string | null>(null);

  async function copy() {
    try {
      await navigator.clipboard.writeText(lessonBrief(words, events));
      setStatus("Copied");
    } catch {
      setStatus("Couldn't copy");
    }
    setTimeout(() => setStatus(null), 1800);
  }

  return (
    <div className="share">
      <button type="button" onClick={() => void copy()}>
        Copy All for AI Lesson
      </button>
      {status && <span className="sub">{status}</span>}
    </div>
  );
}
