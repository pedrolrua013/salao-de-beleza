import { test } from "node:test";
import assert from "node:assert/strict";
import { MODELO_EQUIPE, parametrosEquipe, type AvisoEquipe } from "./avisos-equipe.ts";

const base = { id: "a1", salao_id: "s1", wa_id: "5511955550002", membro_nome: "Bruno Lima", fuso: "America/Sao_Paulo" };

test("horário novo com cliente, serviço, dia e hora", () => {
  const a: AvisoEquipe = { ...base, tipo: "novo", dados: { cliente: "Maria Silva", servico: "Escova", inicio: "2026-11-06T17:00:00Z" } };
  const p = parametrosEquipe(a);
  assert.deepEqual(p.slice(0, 3), ["Bruno", "horário novo", "Maria Silva"]);
  assert.match(p[3], /^Escova, sex\.? 06\/11 às 14:00$/);
  assert.match(MODELO_EQUIPE.corpo.replace(/\{\{(\d)\}\}/g, (_, n) => p[Number(n) - 1]), /^Bruno, horário novo na sua agenda: Maria Silva, Escova/);
});

test("remarcado mostra de quando para quando", () => {
  const a: AvisoEquipe = { ...base, tipo: "mudou", dados: { cliente: "Maria", servico: "Corte", inicio: "2026-11-06T18:00:00Z", inicio_antigo: "2026-11-06T17:00:00Z" } };
  assert.match(parametrosEquipe(a)[3], /^Corte, de sex\.? 06\/11 às 14:00 para sex\.? 06\/11 às 15:00$/);
});
