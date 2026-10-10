import { Mastery, masteryLabel } from "../core/models";

const marks: Record<Mastery, string> = { [Mastery.NotYet]: "✕", [Mastery.Unsure]: "?", [Mastery.Known]: "✓" };

// Book の ✕ / ? / ✓。色だけに頼らず、記号でも見分けられるようにする
export function MasteryMark({ mastery }: { mastery: Mastery }) {
  return (
    <span className={`mark mark-${mastery}`} aria-label={masteryLabel[mastery]} title={masteryLabel[mastery]}>
      {marks[mastery]}
    </span>
  );
}
