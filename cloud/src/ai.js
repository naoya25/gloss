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

// スマホの翻訳。英文の語句を全部「英語 | 日本語 | 難しさ」の形で書かせ、どこまで英語で読むかはスマホが決める。
// 指示文は Mac の Prompts.gradedTranslation と同じにする。片方を変えたら、もう片方も変える。
// 長い英文はスマホが段落ごとに分けて送るので、1回に受け取る長さは決めておく
const MAX_SOURCE = 4000;
const MAX_KNOWN = 300;

export async function translateGraded(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const text = body?.text;
  const known = Array.isArray(body?.known) ? body.known : [];
  if (typeof text !== "string" || !text.trim() || text.length > MAX_SOURCE) return json({ error: "bad text" }, 400);
  if (known.length > MAX_KNOWN || !known.every((term) => typeof term === "string" && term.length <= 80)) return json({ error: "bad known" }, 400);
  const response = await fetch(`https://api.japan-ai.co.jp/v1/chat/completions?userId=${encodeURIComponent(env.JAI_USER_ID)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.AI_KEY}` },
    body: JSON.stringify({
      model: env.AI_MODEL,
      stream: false,
      messages: [
        { role: "system", content: gradedTranslationPrompt(known) },
        { role: "user", content: text },
      ],
    }),
  });
  if (!response.ok) return json({ error: `ai ${response.status}` }, 502);
  const result = await response.json();
  return json({ raw: result?.choices?.[0]?.message?.content ?? "" });
}

export function gradedTranslationPrompt(known) {
  const open = "⟦";
  const close = "⟧";
  let prompt = `あなたはプロの翻訳者です。入力の英文を、要約・省略せずに自然な日本語へ全文翻訳してください。出力は訳文のみとし、前置きや説明を含めないでください。
ただし、英文の中の意味のある語句(名詞句・動詞句・形容詞・副詞・慣用表現。1〜4語程度)は、訳文の中で全部次の形で書いてください。英文の単語の7割以上が、この形のどれかに入るようにしてください。
${open}<英文での表記> | <その部分の日本語訳> | <難しさ>${close}
- 難しさは、日本人のソフトウェアエンジニアにとっての難しさを 1〜5 の整数で書いてください。1: 中学で習う語(meeting, check)、3: 仕事でよく見る語(deploy, deadline)、5: 難しい語や慣用表現(rule of thumb, mitigate)
- 学習者はこの形の部分を英語のまま読むことがあります。英語のまま差し込んでも日本語の文として自然になるよう、前後の助詞や語順を整えてください(例: 「${open}hotfix | 緊急修正 | 3${close}を出しました」)
- 動詞は原形(push, migrate)で書き、日本語訳は語幹だけ(プッシュ、移行)にして、「する」「しました」「している」などの活用は形の外に書いてください(例: 「${open}push | プッシュ | 2${close}しました」「${open}migrate | 移行 | 3${close}する予定です」)
- 形容詞も同じく、「な」「に」は形の外に書いてください(例: 「${open}stable | 安定 | 2${close}な」)
- 形の中の日本語と同じ言葉を、形の外で繰り返さないでください(誤: 「主な${open}main goal | 主な目標 | 2${close}」)
- FYI・ASAP などの略語や挨拶も語句として囲んでください
- 冠詞・前置詞・代名詞・be 動詞だけの部分は囲まず、普通に訳してください。製品名・人名・コード・URL は原文のままにし、囲まないでください
- 入力の英文に無い内容を訳文に足さないでください
入力が Markdown 記法を含む場合は記法を保ってください。
`;
  if (known.length) prompt += `\n# 学習者が覚えた表現(英文に出てきたら、必ずひとかたまりの語句として囲んでください)\n${known.map((term) => `- ${term}`).join("\n")}`;
  return prompt;
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
