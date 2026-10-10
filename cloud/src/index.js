// Gloss の単語帳と学習の記録を D1 に置く API。
// 単語は1単語を1行で持ち、updated_at が新しい書き込みだけを受け入れる(後から書いたほうが勝つ)。
// 記録は足すだけで、書き換えない
const PAGE_SIZE = 500;
const MAX_ROWS_PER_PUSH = 200;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!(await authorized(request, env))) return json({ error: "unauthorized" }, 401);

    if (url.pathname === "/api/words" && request.method === "GET") {
      return pull(env, Number(url.searchParams.get("since") ?? 0));
    }
    if (url.pathname === "/api/words" && request.method === "POST") {
      return push(request, env);
    }
    if (url.pathname === "/api/activity" && request.method === "GET") {
      return pullActivity(env, Number(url.searchParams.get("since") ?? 0));
    }
    if (url.pathname === "/api/activity" && request.method === "POST") {
      return pushActivity(request, env);
    }
    return json({ error: "not found" }, 404);
  },
};

// 前回取りに来た seq より後に書かれた行を返す。消した単語も deleted として返す
async function pull(env, since) {
  if (!Number.isInteger(since) || since < 0) return json({ error: "bad since" }, 400);
  const { results } = await env.DB.prepare(
    "SELECT id, data, updated_at, deleted, seq FROM words WHERE seq > ? ORDER BY seq LIMIT ?",
  )
    .bind(since, PAGE_SIZE)
    .all();
  const words = results.map((row) => ({
    id: row.id,
    updatedAt: row.updated_at,
    deleted: row.deleted === 1,
    data: row.data ? JSON.parse(row.data) : null,
  }));
  const cursor = results.length ? results[results.length - 1].seq : since;
  return json({ words, cursor, hasMore: results.length === PAGE_SIZE });
}

async function push(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const rows = Array.isArray(body?.words) ? body.words : null;
  if (!rows || rows.length > MAX_ROWS_PER_PUSH || !rows.every(isValidRow)) {
    return json({ error: "bad words" }, 400);
  }
  // 手元より古い書き込みは捨てる。受け入れた行だけ seq を進める
  const statement = env.DB.prepare(
    `INSERT INTO words (id, data, updated_at, deleted, seq)
     VALUES (?1, ?2, ?3, ?4, (SELECT COALESCE(MAX(seq), 0) + 1 FROM words))
     ON CONFLICT (id) DO UPDATE SET
       data = excluded.data, updated_at = excluded.updated_at,
       deleted = excluded.deleted, seq = excluded.seq
     WHERE excluded.updated_at > words.updated_at`,
  );
  if (rows.length) {
    await env.DB.batch(
      rows.map((row) =>
        statement.bind(row.id, row.deleted ? null : JSON.stringify(row.data), row.updatedAt, row.deleted ? 1 : 0),
      ),
    );
  }
  return json({ ok: true });
}

async function pullActivity(env, since) {
  if (!Number.isInteger(since) || since < 0) return json({ error: "bad since" }, 400);
  const { results } = await env.DB.prepare(
    "SELECT id, kind, date, word_id, data, seq FROM activity WHERE seq > ? ORDER BY seq LIMIT ?",
  )
    .bind(since, PAGE_SIZE)
    .all();
  const events = results.map((row) => ({
    id: row.id,
    kind: row.kind,
    date: row.date,
    wordID: row.word_id ?? undefined,
    data: JSON.parse(row.data),
  }));
  const cursor = results.length ? results[results.length - 1].seq : since;
  return json({ events, cursor, hasMore: results.length === PAGE_SIZE });
}

// 記録は書き換えないので、同じ id がもうあれば何もしない
async function pushActivity(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const rows = Array.isArray(body?.events) ? body.events : null;
  if (!rows || rows.length > MAX_ROWS_PER_PUSH || !rows.every(isValidActivity)) {
    return json({ error: "bad events" }, 400);
  }
  const statement = env.DB.prepare(
    `INSERT INTO activity (id, kind, date, word_id, data, seq)
     VALUES (?1, ?2, ?3, ?4, ?5, (SELECT COALESCE(MAX(seq), 0) + 1 FROM activity))
     ON CONFLICT (id) DO NOTHING`,
  );
  if (rows.length) {
    await env.DB.batch(
      rows.map((row) => statement.bind(row.id, row.kind, row.date, row.wordID ?? null, JSON.stringify(row.data))),
    );
  }
  return json({ ok: true });
}

function isValidActivity(row) {
  return (
    typeof row?.id === "string" &&
    row.id.length > 0 &&
    row.id.length <= 64 &&
    typeof row.kind === "string" &&
    row.kind.length <= 32 &&
    Number.isSafeInteger(row.date) &&
    (row.wordID == null || (typeof row.wordID === "string" && row.wordID.length <= 64)) &&
    typeof row.data === "object" &&
    row.data !== null &&
    row.data.id === row.id
  );
}

function isValidRow(row) {
  return (
    typeof row?.id === "string" &&
    row.id.length > 0 &&
    row.id.length <= 64 &&
    Number.isSafeInteger(row.updatedAt) &&
    typeof row.deleted === "boolean" &&
    (row.deleted || (typeof row.data === "object" && row.data !== null && row.data.id === row.id))
  );
}

// トークンは長さを揃えてから比べる。比べる時間から中身を推測されないようにするため
async function authorized(request, env) {
  const header = request.headers.get("Authorization") ?? "";
  if (!env.SYNC_TOKEN || !header.startsWith("Bearer ")) return false;
  const [given, expected] = await Promise.all([digest(header.slice(7)), digest(env.SYNC_TOKEN)]);
  return crypto.subtle.timingSafeEqual(given, expected);
}

async function digest(text) {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
