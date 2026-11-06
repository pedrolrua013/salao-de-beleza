import { STATUS, type Status } from "@/lib/types";

const ICONES: Record<string, React.ReactNode> = {
  check: <path d="M5 12l5 5L20 7" />,
  clock: (<><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>),
  x: <path d="M6 6l12 12M18 6L6 18" />,
  chat: <path d="M5 5h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-6l-4 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />,
};

/** Status sempre com palavra e ícone, nunca só cor. */
export function Selo({ status }: { status: Status }) {
  const s = STATUS[status];
  return (
    <span className={`bd ${s.classe}`}>
      <svg viewBox="0 0 24 24" aria-hidden="true">{ICONES[s.icone]}</svg>
      {s.texto}
    </span>
  );
}
