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

-- 学習の記録。何をやったかはこの表だけを正とする。一度書いた行は書き換えない。
-- word_id は単語を保存した・めくったときの words.id(テストの1問ずつの単語は data の answers に入る)
CREATE TABLE IF NOT EXISTS activity (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  date INTEGER NOT NULL,
  word_id TEXT,
  data TEXT NOT NULL,
  seq INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS activity_seq ON activity (seq);
CREATE INDEX IF NOT EXISTS activity_date ON activity (date);
