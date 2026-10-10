// スマホの単語テストの採点。指示文はここで組み立て、スマホからは問題と答えしか受け取らない。
// 合言葉が漏れても、採点以外に AI を使われないようにするため。
// 指示文は Mac の Prompts.wordTestReview と同じにする。片方を変えたら、もう片方も変える
const MAX_ITEMS = 10;
const MAX_TEXT = 200;

export async function gradeWordTest(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const direction = body?.direction;
  const items = Array.isArray(body?.items) ? body.items : null;
  if (!["toEnglish", "toJapanese"].includes(direction) || !items || !items.length || items.length > MAX_ITEMS || !items.every(isValidItem)) {
    return json({ error: "bad items" }, 400);
  }
  const response = await fetch(`https://api.japan-ai.co.jp/v1/chat/completions?userId=${encodeURIComponent(env.JAI_USER_ID)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.AI_KEY}` },
    body: JSON.stringify({ model: env.AI_MODEL, stream: false, messages: [{ role: "user", content: wordTestPrompt(direction, items) }] }),
  });
  if (!response.ok) return json({ error: `ai ${response.status}` }, 502);
  const result = await response.json();
  const text = result?.choices?.[0]?.message?.content ?? "";
  return json({ grades: parseGrades(text) });
}

function isValidItem(item) {
  return (
    Number.isInteger(item?.number) &&
    item.number >= 1 &&
    item.number <= MAX_ITEMS &&
    ["prompt", "expected", "answer"].every((key) => typeof item[key] === "string" && item[key].length <= MAX_TEXT)
  );
}

export function wordTestPrompt(direction, items) {
  const task =
    direction === "toEnglish"
      ? "学習者は日本語を見て、それに当たる英語を書きました。\n「想定の答え」と違っても、日本語の意味で同じように使える英語なら正解にしてください。"
      : "学習者は英語を見て、その意味を日本語で書きました。\n「想定の答え」と違っても、この英語の意味として正しい日本語なら正解にしてください。";
  let prompt = `英単語テストを採点してください。${task}
判定は次の3つです。
O: 正解(綴りの小さな誤りも含む)
?: 惜しい(意味は近いが、品詞・ニュアンス・決まった言い方がずれている)
X: 不正解
問題ごとに1行ずつ、次の形式だけを出力してください。コメントは日本語で短く。
<番号>: <O か ? か X> | <コメント>

`;
  for (const item of items) {
    prompt += `${item.number}. 問題: ${item.prompt} / 想定の答え: ${item.expected} / 学習者の答え: ${item.answer}\n`;
  }
  return prompt;
}

// 「1: O | コメント」の行を読む。判定は Book の覚えた度合い(0 = Not Yet / 1 = Unsure / 2 = Known)で返す
export function parseGrades(text) {
  const grades = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.trim().match(/^(\d+)\s*[:：]\s*([^|]+?)\s*(?:\|\s*(.*))?$/);
    if (!match) continue;
    const verdict = { O: 2, "○": 2, "◯": 2, "?": 1, "？": 1, X: 0, "×": 0, "✕": 0 }[match[2].toUpperCase()];
    if (verdict === undefined) continue;
    grades[match[1]] = { verdict, comment: match[3] ?? "" };
  }
  return grades;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
