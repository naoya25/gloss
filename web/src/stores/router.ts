import { create } from "zustand";

export type Route = "book" | "test" | "report";

export const routes: { route: Route; label: string }[] = [
  { route: "book", label: "Book" },
  { route: "test", label: "Test" },
  { route: "report", label: "Report" },
];

interface RouterState {
  route: Route;
  go: (route: Route) => void;
}

export const useRouter = create<RouterState>()((setState) => ({
  route: "book",
  go: (route) => setState({ route }),
}));
