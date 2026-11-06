import { test } from "node:test";
import assert from "node:assert/strict";
import { clienteDaLinha, detectarMapa, lerNascimento, lerTelefone, letraColuna, prepararClientes, validarImportado } from "./importar-clientes.ts";
import { lerCsv } from "./csv.ts";

test("reconhece colunas de outros sistemas, inclusive com nome diferente", () => {
  const { mapa, temCabecalho } = detectarMapa(["Nome do Cliente", "Telefone Celular", "E-mail", "Data de Nascimento", "CEP", "Endereço", "Nº", "Bairro", "Cidade", "UF", "Obs"]);
  assert.equal(temCabecalho, true);
  assert.deepEqual([mapa.nome, mapa.telefone, mapa.email, mapa.nascimento, mapa.cep, mapa.logradouro, mapa.numero, mapa.bairro, mapa.cidade, mapa.uf, mapa.observacoes], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.equal(mapa.complemento, -1);
  assert.equal(detectarMapa(["Celular (WhatsApp)", "Nome"]).mapa.telefone, 0);
});

test("planilha sem cabeçalho: adivinha nome, celular e e-mail pelo conteúdo", () => {
  const { mapa, temCabecalho } = detectarMapa(["Ana Souza", "(11) 99999-0000", "ana@x.com"]);
  assert.equal(temCabecalho, false);
  assert.deepEqual([mapa.nome, mapa.telefone, mapa.email], [0, 1, 2]);
});

test("celular: tira +55 e zero, completa o DDD do salão, recusa o que não dá", () => {
  assert.equal(lerTelefone("+55 (11) 98888-7777", null), "11988887777");
  assert.equal(lerTelefone("011 3333-4444", null), "1133334444");
  assert.equal(lerTelefone("011 98888-7777", "13"), "11988887777", "o DDD da planilha vale, não o do salão");
  assert.equal(lerTelefone("015 11 98888-7777", null), "11988887777", "zero + operadora + DDD");
  assert.equal(lerTelefone("015 11 3333-4444", null), "1133334444");
  assert.equal(lerTelefone("98888-7777", "13"), "13988887777");
  assert.equal(lerTelefone("98888-7777", null), null);
  assert.equal(lerTelefone("123", "13"), null);
  assert.equal(lerTelefone("11988887777", null), "11988887777");
});

test("nascimento em texto ou número do Excel", () => {
  assert.equal(lerNascimento("31/12/1990"), "1990-12-31");
  assert.equal(lerNascimento("33238"), "1990-12-31");
  assert.equal(lerNascimento("1990-12-31 00:00:00"), "1990-12-31");
  assert.equal(lerNascimento("12"), null);
});

test("linha vira cliente; celular ruim vai para as observações", () => {
  const { mapa } = detectarMapa(["Nome", "Celular", "E-mail", "CEP", "UF", "Obs"]);
  const r = clienteDaLinha(["  Marina   Souza ", "123", "MARINA@X.COM", "1430090", "sp", "gosta de café"], mapa, "13");
  assert.ok("cliente" in r);
  assert.equal(r.cliente.nome, "Marina Souza");
  assert.equal(r.cliente.telefone, null);
  assert.equal(r.cliente.email, "marina@x.com");
  assert.equal(r.cliente.cep, "01430090");
  assert.equal(r.cliente.uf, "SP");
  assert.equal(r.cliente.observacoes, "Telefone na planilha: 123\ngosta de café");
  assert.deepEqual(r.avisos, ["celular incompleto"]);
  assert.deepEqual(clienteDaLinha(["", "11999990000"], mapa, null), { ignorada: "sem nome" });
  assert.deepEqual(clienteDaLinha(["123", "11999990000"], mapa, null), { ignorada: "sem nome" });
});

test("repetidas dentro da planilha entram uma vez só", () => {
  const linhas = lerCsv("Nome;Celular\nAna;11999990000\nAna Souza;+55 11 99999-0000\nBia;\nbia;\n;11988880000");
  const { mapa } = detectarMapa(linhas[0]);
  const r = prepararClientes(linhas.slice(1), mapa, null);
  assert.deepEqual(r.clientes.map((c) => c.nome), ["Ana", "Bia"]);
  assert.equal(r.repetidasNaPlanilha, 2);
  assert.equal(r.semNome, 1);
});

test("o servidor confere tudo de novo", () => {
  assert.equal(validarImportado({ nome: "A" }), null);
  assert.equal(validarImportado("x"), null);
  const v = validarImportado({ nome: "Ana", telefone: "999", email: "x", nascimento: "2090-01-01", uf: "XX", cep: "11430090", bairro: "Centro" });
  assert.deepEqual(v && [v.telefone, v.email, v.nascimento, v.uf, v.cep, v.bairro], [null, null, null, null, "11430090", "Centro"]);
});

test("letras das colunas", () => {
  assert.deepEqual([0, 25, 26, 27, 51, 52].map(letraColuna), ["A", "Z", "AA", "AB", "AZ", "BA"]);
});
