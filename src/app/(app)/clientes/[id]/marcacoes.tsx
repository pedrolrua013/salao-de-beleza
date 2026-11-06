import { marcarCliente } from "./actions";

/** VIP (não paga sinal, estrela na agenda), sempre paga sinal, e bloqueada (não marca sozinha pelo link nem pelo WhatsApp). */
export function MarcacoesCliente({ id, vip, bloqueada, sempreSinal, faltas }: { id: string; vip: boolean; bloqueada: boolean; sempreSinal: boolean; faltas: number }) {
  const botao = (campo: string, ligado: boolean, texto: string, classe = "btn ghost sm") => (
    <form action={marcarCliente}><input type="hidden" name="id" value={id} /><input type="hidden" name="campo" value={campo} /><input type="hidden" name="valor" value={ligado ? "0" : "1"} />
      <button className={`${classe}${ligado ? " on" : ""}`} type="submit" aria-pressed={ligado}>{texto}</button></form>
  );
  return (
    <div className="row marcacoes" style={{ gap: 6 }}>
      {botao("vip", vip, vip ? "★ VIP" : "☆ Marcar como VIP")}
      {botao("sempre_sinal", sempreSinal, sempreSinal ? "Sempre paga sinal" : "Pedir sinal sempre")}
      {botao("bloqueada", bloqueada, bloqueada ? "Desbloquear" : "Bloquear marcação sozinha")}
      {faltas >= 2 && !sempreSinal && !bloqueada && <span className="cap" style={{ color: "var(--warning-text)" }}>Faltou {faltas} vezes: considere pedir sinal sempre.</span>}
    </div>
  );
}
