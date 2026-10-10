import { get, set } from "idb-keyval";

// 端末の中の控え。ブラウザがデータを消すこともあるので、正は Cloudflare 側に置く
export async function load<T>(key: string, fallback: T): Promise<T> {
  try {
    return ((await get(key)) as T | undefined) ?? fallback;
  } catch {
    return fallback;
  }
}

export async function save(key: string, value: unknown): Promise<void> {
  try {
    await set(key, value);
  } catch {
    // 保存できなくても、画面は動かし続ける。次の同期で取り直せる
  }
}
