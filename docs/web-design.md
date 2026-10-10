# Gloss Web(スマホ向け)の設計

スマホでは、隙間時間に復習するだけに絞る。単語帳と学習の記録は Cloudflare D1 が正なので、Web アプリは今の API を読み書きする薄いアプリにする。

## 1. 最初に作るもの

| 画面 | できること | AI |
|---|---|---|
| Book | カードを押して訳に入れ替える。✕ / ? / ✓ を付ける。並び順の切り替え | 要らない |
| Word Test / Meaning Test | 10問を1枚で書いて、まとめて採点。結果は Book の ✕ / ? / ✓ に入る | 下の「決めること」 |
| Report | Today(今日の数字と記録)と Progress(推移のグラフ) | 要らない |

Translate・Writing Test・Reading Test・質問パネルは、AI を Worker 経由で呼べるようになってから足す。

## 2. 構成

```
web/
├── index.html
├── package.json            Vite + React + TypeScript
├── vite.config.ts          PWA(ホーム画面に置ける・電波が無くても開ける)
└── src/
    ├── main.tsx
    ├── router/             画面の行き先(AppRoute と同じ考え方)
    ├── pages/
    │   ├── book/           page.tsx と store.ts を並べる
    │   ├── test/
    │   └── report/
    ├── stores/             画面をまたぐ状態(words・activity・settings)
    ├── core/               UI に依存しない部分(テストあり)
    │   ├── models.ts       WordEntry・ActivityEvent の型
    │   ├── sync.ts         Mac の WordSync・ActivitySync と同じ合わせ方
    │   ├── quiz.ts         答えの正規化・出題の選び方
    │   └── api.ts          /api/words・/api/activity
    └── widgets/            画面をまたいで使う部品
```

- Mac アプリと同じく、見た目(page)と状態(store)を同じフォルダに置く。store は状態を1つ持ち、書き換えは store の関数からだけにする
- `core/` は Mac の GlossCore に当たる。同期・採点・集計のテストはここに書く(Vitest)
- 配信は今の Worker から行う。`cloud/wrangler.jsonc` の `assets` で `web/dist` を指し、`/api/*` だけ Worker のコードを通す。同じアドレスなので、ブラウザの制限(CORS)の設定が要らない

## 3. データと同期

- API は今のまま使う。`/api/words` は単語ごとに新しい書き込みが勝ち、`/api/activity` は足すだけ
- スマホの中には IndexedDB(ブラウザの中のデータベース)に控えを置く。電波が無いときはそこから表示し、送れなかった変更は貯めておいて、電波が戻ったら送る
- 単語を書き換えるときは、知らない項目も含めて元の JSON を丸ごと残し、変えた項目だけ上書きする。Mac が足した項目を Web が消さないようにする

Mac アプリと食い違うと壊れる約束:

| 項目 | 約束 |
|---|---|
| 日付 | ISO 8601 の秒まで(`2026-10-10T13:00:00Z`)。ミリ秒を付けると Mac が読めない |
| id | UUID は大文字で作る(Mac の `uuidString` と同じ) |
| `mastery` | 0 = Not Yet / 1 = Unsure / 2 = Known |
| `updatedAt`(API の行) | ミリ秒の整数 |
| 記録の `kind` | `cardFlipped`・`wordQuiz`・`meaningQuiz` など、Mac と同じ文字列 |

## 4. ログイン

- 合言葉(`SYNC_TOKEN`)をスマホのブラウザに1回だけ入れて、端末の中に覚えさせる
- 入れ方は QR コード。Mac の設定画面に、URL の `#` の後ろに合言葉を付けた QR を出し、スマホのカメラで読む。`#` の後ろはサーバーに送られない
- ページの外から読み込むスクリプトは使わない(Content-Security-Policy で禁止する)。合言葉を盗まれる穴を作らないため

## 5. 画面の作り

- 下にタブを置く: Book / Test / Report
- 押せる場所は 44pt 以上。カードは1行、押すと文字が入れ替わる(Mac と同じ動き。動きを減らす設定の人には切り替えだけ)
- ライトとダークの両方。iPhone の画面の上下の切り欠きを避ける

## 6. 単語テストの採点(AI は Worker から呼ぶ)

答えが Book と完全に同じならスマホの中で ✓ にして、違うものだけ Worker に送る。Worker が AI に採点させて、✓ / ? / ✕ とコメントを返す。Mac と同じ採点になる。

| 項目 | 決めたこと |
|---|---|
| 窓口 | `POST /api/ai/word-test`。送るのは `{ direction, items: [{ number, prompt, expected, answer }] }` だけ |
| 指示文 | Worker の中で組み立てる。スマホから好きな指示文を送れる汎用の窓口にはしない。合言葉が漏れても、採点以外に AI を使われないようにするため |
| 指示文の中身 | Mac の `Prompts.wordTestReview` と同じ。片方を変えたら、もう片方も変える |
| 量の上限 | 1回 10 問まで、答えは1問 200 字まで |
| API キー | Cloudflare の secret に置く(`AI_KEY`・`AI_MODEL`。JAPAN AI なら `JAI_USER_ID` も)。キーはコードにも git にも入れない |
| 失敗したとき | 採点できなかった問題だけ、正解を見せて自分で ✓ / ? / ✕ を押せるようにする |

Writing Test と Reading Test も、あとで同じ形(Worker の中で指示文を組み立てる専用の窓口)で足す。

> [!WARNING]
> 会社の API キーを Cloudflare に置くことになる。社外のサーバーにキーを置いていいかは、会社のルールで確かめる。
