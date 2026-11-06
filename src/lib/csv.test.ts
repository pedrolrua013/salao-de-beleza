import { test } from "node:test";
import assert from "node:assert/strict";
import { escreverCsv, lerCsv, lerData } from "./csv.ts";

test("lê CSV com ponto e vírgula, aspas e quebra de linha no campo", () => {
  const l = lerCsv('﻿Nome;Celular;Obs\r\n"Silva; Ana";(11) 99999-0000;"linha 1\nlinha 2"\r\n\r\nBia;;\n');
  assert.deepEqual(l, [["Nome", "Celular", "Obs"], ["Silva; Ana", "(11) 99999-0000", "linha 1\nlinha 2"], ["Bia", "", ""]]);
});

test("lê CSV com vírgula e aspas duplas escapadas", () => {
  assert.deepEqual(lerCsv('nome,email\n"Ana ""Aninha""",a@b.com'), [["nome", "email"], ['Ana "Aninha"', "a@b.com"]]);
});

test("texto colado do Excel vem com tabulação", () => {
  assert.deepEqual(lerCsv("Nome\tCelular\nAna, Maria\t11999990000"), [["Nome", "Celular"], ["Ana, Maria", "11999990000"]]);
});

test("datas em vários formatos", () => {
  assert.equal(lerData("1985-07-04"), "1985-07-04");
  assert.equal(lerData("4/7/85"), "1985-07-04");
  assert.equal(lerData("31/04/2000"), null);
  assert.equal(lerData("ontem"), null);
});

test("célula que parece fórmula vira texto", () => {
  assert.equal(escreverCsv(["Nome"], [["=HIPERLINK(\"x\")"], ["@SOMA(1)"], ["Ana"], [-5]]), "\uFEFFNome\r\n\"'=HIPERLINK(\"\"x\"\")\"\r\n'@SOMA(1)\r\nAna\r\n-5");
});

test("escreve CSV que o Excel abre com acentos", () => {
  const csv = escreverCsv(["Nome", "Obs"], [["Ana", 'diz "oi"; tchau'], ["Bia", null]]);
  assert.equal(csv, '﻿Nome;Obs\r\nAna;"diz ""oi""; tchau"\r\nBia;');
});
