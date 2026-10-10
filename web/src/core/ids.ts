// Mac(Swift)の日付は秒までの ISO 8601 しか読めないので、ミリ秒を落とす
export function isoSeconds(date: Date = new Date()): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

// Mac の UUID.uuidString に合わせて大文字にする
export function newID(): string {
  return crypto.randomUUID().toUpperCase();
}

export const millis = (iso: string | undefined) => (iso ? Date.parse(iso) : 0);
