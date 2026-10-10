-- data は Gloss の WordEntry をそのまま JSON にしたもの。
-- seq は書き込むたびに増える番号で、端末は前回の seq より後の行だけを取りに来る
CREATE TABLE IF NOT EXISTS words (
  id TEXT PRIMARY KEY,
  data TEXT,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  seq INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS words_seq ON words (seq);
