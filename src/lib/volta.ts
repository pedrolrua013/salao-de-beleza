/** Para onde voltar depois de um cadastro: só caminhos internos do sistema (nada de "//outro-site" ou "https://"). */
export function voltaSegura(v: unknown): string | null {
  const s = typeof v === "string" ? v : "";
  return s.length <= 300 && /^\/(?![/\\])[\w\-/?=&%.~]*$/.test(s) ? s : null;
}
