import { useState } from "react";
import { useSession } from "../../stores/session";

export function LoginPage() {
  const error = useSession((state) => state.error);
  const signIn = useSession((state) => state.signIn);
  const [token, setToken] = useState("");
  return (
    <section className="page login">
      <img src="/icon.svg" alt="" width="72" height="72" />
      <h1>Gloss</h1>
      <p className="sub">Scan the QR code in Gloss settings on your Mac, or paste the sync token.</p>
      {error && <p className="error">{error}</p>}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (token.trim()) signIn(token.trim());
        }}
      >
        <input type="password" value={token} placeholder="Sync token" autoComplete="current-password" onChange={(event) => setToken(event.target.value)} />
        <button type="submit" className="primary">Open</button>
      </form>
    </section>
  );
}
