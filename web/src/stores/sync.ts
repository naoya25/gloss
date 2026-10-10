import { createApi, Unauthorized, type Api } from "../core/api";
import { useSession } from "./session";

// 合言葉が違うと分かったら、ログインの画面に戻す
export function currentApi(): Api | null {
  const { token } = useSession.getState();
  return token ? createApi(token) : null;
}

export function handleSyncError(error: unknown): string {
  if (error instanceof Unauthorized) {
    useSession.getState().signOut("The token is wrong. Scan the QR code in Gloss settings again.");
    return "unauthorized";
  }
  return navigator.onLine ? "Couldn't sync. It will retry." : "Offline. Changes will be sent later.";
}
