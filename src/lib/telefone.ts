// Máscara de telefone brasileiro: "13999990000" → "(13) 99999-0000". O servidor sempre guarda só os números.

/** Só os números, no máximo 11 (DDD + celular). Um 55 do país na frente é tirado. */
export function digitosTelefone(texto: string): string {
  let d = texto.replace(/\D/g, "");
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  return d.slice(0, 11);
}

/** Formata enquanto a pessoa digita: (13) 9999-0000 para fixo, (13) 99999-0000 para celular. */
export function formatarTelefone(texto: string): string {
  const d = digitosTelefone(texto);
  if (d.length === 0) return "";
  if (d.length <= 2) return `(${d}`;
  const ddd = d.slice(0, 2), resto = d.slice(2);
  if (resto.length <= 4) return `(${ddd}) ${resto}`;
  const corte = resto.length === 9 ? 5 : 4;
  return `(${ddd}) ${resto.slice(0, corte)}-${resto.slice(corte)}`;
}
