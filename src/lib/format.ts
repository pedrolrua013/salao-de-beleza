export function hora(iso: string, tz: string) {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: tz, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(iso));
}
export function dataCurta(iso: string, tz: string) {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: tz, day: "2-digit", month: "2-digit", year: "numeric" }).format(new Date(iso));
}
/** "2026-11-02" → "segunda-feira, 2 de novembro" */
export function dataLonga(ymd: string) {
  const [y, m, d] = ymd.split("-").map(Number);
  const t = new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC", weekday: "long", day: "numeric", month: "long" }).format(new Date(Date.UTC(y, m - 1, d)));
  // "Terça-feira, 3 de novembro": só a primeira letra maiúscula (capitalize no CSS faria "3 De Novembro").
  return t.charAt(0).toUpperCase() + t.slice(1);
}
export function dataBR(ymd: string) {
  const [y, m, d] = ymd.split("-");
  return `${d}/${m}/${y}`;
}
export function telefone(v: string | null) {
  if (!v) return "";
  const n = v.replace(/\D/g, "");
  if (n.length === 11) return `(${n.slice(0, 2)}) ${n.slice(2, 7)}-${n.slice(7)}`;
  if (n.length === 10) return `(${n.slice(0, 2)}) ${n.slice(2, 6)}-${n.slice(6)}`;
  return v;
}
export function soDigitos(v: string) {
  return v.replace(/\D/g, "");
}
export function idade(nascimento: string | null) {
  if (!nascimento) return null;
  const n = new Date(nascimento), h = new Date();
  let a = h.getFullYear() - n.getFullYear();
  if (h.getMonth() < n.getMonth() || (h.getMonth() === n.getMonth() && h.getDate() < n.getDate())) a--;
  return a;
}
