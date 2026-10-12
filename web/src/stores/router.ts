import { create } from "zustand";

export type Route = "translate" | "book" | "choice" | "test" | "report";

export const routes: { route: Route; label: string }[] = [
  { route: "translate", label: "Translate" },
  { route: "book", label: "Book" },
  { route: "choice", label: "4-Choice" },
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
