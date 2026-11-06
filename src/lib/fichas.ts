// Perguntas da ficha de primeira visita para cada área de estética (cabelo continua com as perguntas próprias da ficha).

export type Pergunta = { chave: string; texto: string; tipo: "simnao" | "simnaons" | "opcoes" | "texto"; opcoes?: string[] };
export type Area = "cabelo" | "unhas" | "cilios_sobrancelha" | "pele" | "depilacao";

export const AREAS_FICHA: Record<Exclude<Area, "cabelo">, { titulo: string; perguntas: Pergunta[] }> = {
  unhas: { titulo: "Unhas", perguntas: [
    { chave: "un_servico", texto: "O que você costuma fazer?", tipo: "opcoes", opcoes: ["Esmaltação comum", "Esmaltação em gel", "Alongamento (fibra ou acrigel)", "Spa dos pés"] },
    { chave: "un_alergia", texto: "Já teve alergia a esmalte, gel ou acrigel?", tipo: "simnaons" },
    { chave: "un_fungo", texto: "Tem ou teve micose ou fungo nas unhas?", tipo: "simnaons" },
    { chave: "un_diabetes", texto: "Tem diabetes ou problema de circulação?", tipo: "simnao" },
  ] },
  cilios_sobrancelha: { titulo: "Cílios e sobrancelha", perguntas: [
    { chave: "ci_alergia", texto: "Tem alergia a cola de cílios, henna ou tintura?", tipo: "simnaons" },
    { chave: "ci_lente", texto: "Usa lente de contato?", tipo: "simnao" },
    { chave: "ci_olhos", texto: "Está com alguma irritação nos olhos (conjuntivite, olho seco, blefarite)?", tipo: "simnao" },
    { chave: "ci_feito", texto: "Já fez extensão de cílios, lash lifting ou design com henna?", tipo: "simnao" },
  ] },
  pele: { titulo: "Pele", perguntas: [
    { chave: "pe_tipo", texto: "Como é sua pele?", tipo: "opcoes", opcoes: ["Oleosa", "Seca", "Mista", "Normal", "Sensível", "Não sei"] },
    { chave: "pe_acidos", texto: "Usa ácidos, retinoides ou remédio para acne (ex.: Roacutan)?", tipo: "simnaons" },
    { chave: "pe_condicao", texto: "Tem acne inflamada, rosácea, melasma ou herpes ativa?", tipo: "simnaons" },
    { chave: "pe_sol", texto: "Vai pegar sol forte nos próximos dias?", tipo: "simnao" },
  ] },
  depilacao: { titulo: "Depilação", perguntas: [
    { chave: "de_metodo", texto: "Qual método prefere?", tipo: "opcoes", opcoes: ["Cera quente", "Cera fria", "Linha", "Laser ou luz pulsada"] },
    { chave: "de_reacao", texto: "Já teve reação, mancha ou queimadura com cera?", tipo: "simnaons" },
    { chave: "de_pele", texto: "Tem varizes, feridas ou pele muito sensível na região?", tipo: "simnaons" },
    { chave: "de_acidos", texto: "Usa ácidos ou remédio para acne (ex.: Roacutan)?", tipo: "simnaons" },
  ] },
};

export const ROTULO_RESPOSTA: Record<string, string> = { sim: "Sim", nao: "Não", ns: "Não sei" };

/** Lê do formulário as respostas das áreas que o salão atende (só valores esperados, com tamanho limitado). */
export function lerRespostasAreas(f: FormData, areas: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const a of areas) {
    const def = AREAS_FICHA[a as keyof typeof AREAS_FICHA];
    if (!def) continue;
    for (const p of def.perguntas) {
      const v = String(f.get(p.chave) ?? "").trim();
      if (!v) continue;
      if ((p.tipo === "simnao" || p.tipo === "simnaons") && ["sim", "nao", "ns"].includes(v)) out[p.chave] = v;
      else if (p.tipo === "opcoes" && p.opcoes?.includes(v)) out[p.chave] = v;
      else if (p.tipo === "texto") out[p.chave] = v.slice(0, 200);
    }
  }
  return out;
}

/** Perguntas e respostas para mostrar na ficha da cliente. */
export function respostasDasAreas(r: Record<string, string> | null | undefined): { area: string; pergunta: string; resposta: string }[] {
  if (!r) return [];
  return Object.values(AREAS_FICHA).flatMap((a) => a.perguntas.filter((p) => r[p.chave]).map((p) => ({ area: a.titulo, pergunta: p.texto, resposta: ROTULO_RESPOSTA[r[p.chave]] ?? r[p.chave] })));
}
