import { test } from "node:test";
import assert from "node:assert/strict";
import { lerPermissoes, pode } from "./permissoes.ts";

test("administrador pode tudo; os outros seguem o padrão do papel", () => {
  assert.equal(pode({ papel: "admin", permissoes: { painel: false } }, "painel"), true);
  assert.equal(pode({ papel: "recepcao" }, "painel"), false);
  assert.equal(pode({ papel: "recepcao" }, "estoque"), true);
  assert.equal(pode({ papel: "profissional" }, "estoque"), false);
  assert.equal(pode({ papel: "profissional", permissoes: { desconto: false } }, "desconto"), false);
});

test("caixa: recepção cobra; profissional só se o administrador ligar", () => {
  assert.equal(pode({ papel: "recepcao" }, "caixa"), true);
  assert.equal(pode({ papel: "profissional" }, "caixa"), false);
  assert.equal(pode({ papel: "profissional", permissoes: { caixa: true } }, "caixa"), true);
  assert.deepEqual(lerPermissoes("profissional", ["caixa", "desconto", "agenda_outros"]), { caixa: true });
});

test("grava só o que muda do padrão", () => {
  assert.deepEqual(lerPermissoes("recepcao", ["painel", "caixa", "desconto", "agenda_outros", "comissoes", "estoque"]), { painel: true });
  assert.deepEqual(lerPermissoes("profissional", ["agenda_outros"]), { desconto: false });
});
