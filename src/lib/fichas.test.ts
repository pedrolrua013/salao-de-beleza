import { test } from "node:test";
import assert from "node:assert/strict";
import { lerRespostasAreas, respostasDasAreas } from "./fichas.ts";

test("lê só as respostas esperadas das áreas do salão", () => {
  const f = new FormData();
  f.set("un_alergia", "sim"); f.set("un_servico", "Esmaltação em gel"); f.set("un_fungo", "talvez"); f.set("pe_tipo", "Oleosa");
  assert.deepEqual(lerRespostasAreas(f, ["unhas"]), { un_alergia: "sim", un_servico: "Esmaltação em gel" });
});

test("mostra pergunta e resposta legíveis", () => {
  assert.deepEqual(respostasDasAreas({ ci_lente: "nao" }), [{ area: "Cílios e sobrancelha", pergunta: "Usa lente de contato?", resposta: "Não" }]);
});
