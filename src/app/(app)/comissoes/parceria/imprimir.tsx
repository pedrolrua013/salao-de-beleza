"use client";

export function Imprimir() {
  return <button className="btn" type="button" onClick={() => window.print()}>Imprimir ou salvar PDF</button>;
}
