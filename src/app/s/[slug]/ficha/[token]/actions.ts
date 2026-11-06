"use server";
import { revalidatePath } from "next/cache";
import { clienteAdmin } from "@/lib/supabase/admin";
import type { Estado } from "@/components/acao-form";
import { lerRespostasAreas } from "@/lib/fichas";

const texto = (f: FormData, k: string, max: number) => String(f.get(k) ?? "").trim().slice(0, max) || undefined;

export async function responderFicha(_: Estado, f: FormData): Promise<Estado> {
  const db = clienteAdmin();
  const token = String(f.get("token") ?? "");
  if (!db || !/^[0-9a-f]{64}$/.test(token)) return { erro: "Link inválido." };
  const respostas = {
    quimica: [...f.getAll("quimica").map(String).map((x) => x.slice(0, 40)).slice(0, 8), ...(texto(f, "quimica_outro", 60) ? [`outra: ${texto(f, "quimica_outro", 60)}`] : [])].join(", ") || undefined,
    quimica_quando: texto(f, "quimica_quando", 80),
    alergias: texto(f, "alergias", 200),
    reacao_tintura: texto(f, "reacao_tintura", 3),
    couro_sensivel: texto(f, "couro_sensivel", 3),
    gestante: texto(f, "gestante", 3),
    medicamento: texto(f, "medicamento", 120),
    objetivo: texto(f, "objetivo", 400),
    nascimento: texto(f, "nascimento", 10),
    origem: texto(f, "origem", 20),
    origem_outro: f.get("origem") === "outro" ? texto(f, "origem_outro", 80) : undefined,
    ...lerRespostasAreas(f, ["unhas", "cilios_sobrancelha", "pele", "depilacao"]),
  };
  const { data } = await db.rpc("responder_ficha", { p_token: token, p_respostas: respostas });
  if (data === "respondida" || data === "ja_respondida") {
    revalidatePath(`/s/${String(f.get("slug") ?? "")}/ficha/${token}`);
    return { ok: "Obrigado! Sua ficha foi enviada para o salão." };
  }
  return { erro: data === "expirada" ? "Este link expirou. Peça um novo ao salão." : "Não foi possível enviar. Tente de novo." };
}
