// Gloss の単語帳を D1 に置く API。
// 1単語を1行で持ち、updated_at が新しい書き込みだけを受け入れる(後から書いたほうが勝つ)
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
