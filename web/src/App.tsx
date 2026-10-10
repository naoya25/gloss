import { useEffect } from "react";
import { BookPage } from "./pages/book/page";
import { LoginPage } from "./pages/login/page";
import { ReportPage } from "./pages/report/page";
import { TestPage } from "./pages/test/page";
import { useActivity } from "./stores/activity";
import { routes, useRouter } from "./stores/router";
import { useSession } from "./stores/session";
import { useWords } from "./stores/words";

export function App() {
  const token = useSession((state) => state.token);
  const route = useRouter((state) => state.route);
  const go = useRouter((state) => state.go);
  const syncError = useWords((state) => state.syncError);

  useEffect(() => {
    if (!token) return;
    void useWords.getState().init();
    void useActivity.getState().init();
    // 画面に戻ってきたときと、電波が戻ったときに、ほかの端末の変更を取ってくる
    const sync = () => {
      if (document.visibilityState !== "visible") return;
      void useWords.getState().sync();
      void useActivity.getState().sync();
    };
    document.addEventListener("visibilitychange", sync);
    window.addEventListener("online", sync);
    return () => {
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("online", sync);
    };
  }, [token]);

  if (!token) return <LoginPage />;

  return (
    <div className="app">
      {syncError && <div className="banner">{syncError}</div>}
      <main>{route === "book" ? <BookPage /> : route === "test" ? <TestPage /> : <ReportPage />}</main>
      <nav className="tabs">
        {routes.map((item) => (
          <button key={item.route} type="button" aria-current={route === item.route ? "page" : undefined} onClick={() => go(item.route)}>
            <TabIcon route={item.route} />
            {item.label}
          </button>
        ))}
      </nav>
    </div>
  );
}

function TabIcon({ route }: { route: string }) {
  const paths: Record<string, string> = {
    book: "M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3V4zm0 13a3 3 0 0 1 3-3h10",
    test: "M9 11l3 3 7-7M20 12v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9",
    report: "M5 20V10m7 10V4m7 16v-7",
  };
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d={paths[route]} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
