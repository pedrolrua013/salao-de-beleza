// Termos para a cliente assinar pelo celular. Os textos prontos são um ponto de partida: o salão pode (e deve) ajustar com o advogado dele.

export type TipoTermo = "quimica" | "imagem" | "outro";
export type ModeloTermo = { id: string; tipo: TipoTermo; titulo: string; texto: string; padrao?: boolean };

export const MODELOS_PADRAO: ModeloTermo[] = [
  {
    id: "padrao:quimica", tipo: "quimica", padrao: true,
    titulo: "Termo de responsabilidade para procedimento químico",
    texto: [
      "Declaro que fui informada sobre o procedimento químico que vou fazer (como coloração, descoloração, mechas, alisamento, progressiva, permanente ou relaxamento), seus cuidados e possíveis riscos, como sensibilidade no couro cabeludo, alteração na textura dos fios, quebra e resultado de cor diferente do esperado por causa de químicas anteriores.",
      "Declaro que as informações que dei sobre alergias, reações anteriores, gestação, amamentação, medicamentos e químicas feitas nos últimos meses são verdadeiras e completas.",
      "Fui orientada sobre o teste de mecha e o teste de alergia (toque) e sei que, se escolhi não fazer, assumo os riscos dessa escolha.",
      "Comprometo-me a seguir os cuidados recomendados depois do procedimento e a avisar o salão se sentir qualquer desconforto.",
    ].join("\n\n"),
  },
  {
    id: "padrao:imagem", tipo: "imagem", padrao: true,
    titulo: "Autorização de uso de imagem",
    texto: [
      "Autorizo o salão a fotografar e filmar o meu cabelo, unhas ou rosto antes, durante e depois do atendimento, e a publicar essas imagens nas suas redes sociais, site, página de agendamento e materiais de divulgação, sem pagamento.",
      "O salão não vai usar a imagem de forma que me ofenda ou prejudique e não vai vender as imagens para outras empresas.",
      "Posso cancelar esta autorização quando quiser, avisando o salão. Depois do aviso, o salão deixa de publicar novas imagens e retira as que estiverem na página de agendamento.",
    ].join("\n\n"),
  },
];

/** CPF com dígitos verificadores certos (aceita com ou sem pontuação). */
export function cpfValido(v: string): boolean {
  const d = v.replace(/\D/g, "");
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
  const dv = (n: number) => {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i);
    const r = (s * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return dv(9) === Number(d[9]) && dv(10) === Number(d[10]);
}

/** Assinatura desenhada: PNG em base64, não vazio e até ~300 KB. */
export function assinaturaValida(v: string): boolean {
  return /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(v) && v.length > 200 && v.length <= 400_000;
}

/** Os modelos do salão; o pronto de química ou de imagem só aparece se o salão não tiver o seu. */
export function modelosDoSalao(proprios: ModeloTermo[]): ModeloTermo[] {
  return [...proprios, ...MODELOS_PADRAO.filter((m) => !proprios.some((p) => p.tipo === m.tipo))];
}
