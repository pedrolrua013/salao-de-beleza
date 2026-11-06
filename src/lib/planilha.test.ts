import { test } from "node:test";
import assert from "node:assert/strict";
import { deflateRawSync } from "node:zlib";
import { decodificarTexto, indiceColuna, lerPlanilha, linhasDaAba } from "./planilha.ts";

/** Monta um .xlsx mínimo (zip) para o teste: o primeiro arquivo guardado, os outros compactados. */
function zip(arqs: Record<string, string>): Uint8Array {
  const partes: Buffer[] = [], central: Buffer[] = [];
  let pos = 0, i = 0;
  for (const [nome, txt] of Object.entries(arqs)) {
    const cru = Buffer.from(txt, "utf8"), comprimir = i++ > 0;
    const dados = comprimir ? deflateRawSync(cru) : cru;
    const n = Buffer.from(nome, "utf8");
    const loc = Buffer.alloc(30); loc.writeUInt32LE(0x04034b50, 0); loc.writeUInt16LE(comprimir ? 8 : 0, 8); loc.writeUInt32LE(dados.length, 18); loc.writeUInt32LE(cru.length, 22); loc.writeUInt16LE(n.length, 26);
    const cen = Buffer.alloc(46); cen.writeUInt32LE(0x02014b50, 0); cen.writeUInt16LE(comprimir ? 8 : 0, 10); cen.writeUInt32LE(dados.length, 20); cen.writeUInt32LE(cru.length, 24); cen.writeUInt16LE(n.length, 28); cen.writeUInt32LE(pos, 42);
    partes.push(loc, n, dados); central.push(cen, n);
    pos += 30 + n.length + dados.length;
  }
  const cd = Buffer.concat(central);
  const fim = Buffer.alloc(22); fim.writeUInt32LE(0x06054b50, 0); fim.writeUInt16LE(central.length / 2, 8); fim.writeUInt16LE(central.length / 2, 10); fim.writeUInt32LE(cd.length, 12); fim.writeUInt32LE(pos, 16);
  return new Uint8Array(Buffer.concat([...partes, cd, fim]));
}

test("lê a primeira aba visível do .xlsx com textos compartilhados e números", async () => {
  const r = await lerPlanilha(zip({
    "xl/workbook.xml": '<workbook><sheets><sheet name="Oculta" sheetId="2" state="hidden" r:id="rId2"/><sheet name="Clientes" sheetId="1" r:id="rId1"/></sheets></workbook>',
    "xl/_rels/workbook.xml.rels": '<Relationships><Relationship Id="rId1" Type="x" Target="worksheets/sheet2.xml"/><Relationship Id="rId2" Type="x" Target="worksheets/sheet1.xml"/></Relationships>',
    "xl/sharedStrings.xml": '<sst><si><t>Nome</t></si><si><t>Celular</t></si><si><r><t xml:space="preserve">Ana </t></r><r><t>&amp; Bia</t></r></si></sst>',
    "xl/worksheets/sheet1.xml": '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>errada</t></is></c></row></sheetData></worksheet>',
    "xl/worksheets/sheet2.xml": '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"/><c r="C2"><v>1.1999990000E10</v></c><c r="D2" s="3"><v>33238</v></c></row></sheetData></worksheet>',
  }));
  assert.deepEqual(r, { linhas: [["Nome", "", "Celular"], ["Ana & Bia", "", "11999990000", "33238"]] });
});

test("formato antigo do Excel pede para salvar como .xlsx", async () => {
  const r = await lerPlanilha(new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0]));
  assert.ok("erro" in r && /\.xls/.test(r.erro));
});

test("CSV antigo do Excel em Latin-1 sai com acento", async () => {
  assert.equal(decodificarTexto(new Uint8Array([0x4a, 0x6f, 0xe3, 0x6f])), "João");
  assert.deepEqual(await lerPlanilha(new TextEncoder().encode("Nome;Cidade\nJoão;Guarujá")), { linhas: [["Nome", "Cidade"], ["João", "Guarujá"]] });
});

test("colunas e células sem referência", () => {
  assert.equal(indiceColuna("AB12"), 27);
  assert.deepEqual(linhasDaAba('<row><c t="inlineStr"><is><t>a</t></is></c><c><v>2</v></c></row><row></row>', []), [["a", "2"]]);
});
