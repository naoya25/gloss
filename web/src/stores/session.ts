import { create } from "zustand";

const KEY = "gloss.token";

function readToken(): string {
  // QR コードから開いたときは、URL の # の後ろに合言葉が付いている。# の後ろはサーバーに送られない
  const fromHash = new URLSearchParams(location.hash.slice(1)).get("token");
  if (fromHash) {
    try {
      localStorage.setItem(KEY, fromHash);
    } catch {}
    history.replaceState(null, "", location.pathname);
    return fromHash;
  }
  try {
    return localStorage.getItem(KEY) ?? "";
  } catch {
    return "";
  }
}

interface SessionState {
  token: string;
  error: string | null;
  signIn: (token: string) => void;
  signOut: (error?: string) => void;
}

export const useSession = create<SessionState>()((setState) => ({
  token: readToken(),
  error: null,
  signIn: (token) => {
    try {
      localStorage.setItem(KEY, token);
    } catch {}
    setState({ token, error: null });
  },
  signOut: (error) => {
    try {
      localStorage.removeItem(KEY);
    } catch {}
    setState({ token: "", error: error ?? null });
  },
}));
