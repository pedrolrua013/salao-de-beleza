"use client";
import { useRef, useState } from "react";
import { formatarTelefone } from "@/lib/telefone";

const digitos = (s: string) => s.replace(/\D/g, "");

/** Campo de telefone com máscara (13) 99999-0000. Envia o texto formatado; o servidor fica só com os números. */
export function CampoTelefone({ id, name, defaultValue, required, autoComplete, placeholder = "(11) 99999-0000" }: {
  id: string; name: string; defaultValue?: string | null; required?: boolean; autoComplete?: string; placeholder?: string;
}) {
  const [valor, setValor] = useState(formatarTelefone(defaultValue ?? ""));
  const ref = useRef<HTMLInputElement>(null);

  function mudar(e: React.ChangeEvent<HTMLInputElement>) {
    const bruto = e.target.value;
    let d = digitos(bruto);
    let antes = digitos(bruto.slice(0, e.target.selectionStart ?? bruto.length)).length;
    // Apagou só um parêntese, espaço ou traço: apaga o número antes dele.
    if (bruto.length < valor.length && d === digitos(valor) && antes > 0) {
      d = d.slice(0, antes - 1) + d.slice(antes);
      antes -= 1;
    }
    const novo = formatarTelefone(d);
    setValor(novo);
    // O cursor fica logo depois do mesmo número em que estava.
    requestAnimationFrame(() => {
      let pos = 0;
      for (let vistos = 0; pos < novo.length && vistos < antes; pos++) if (/\d/.test(novo[pos])) vistos++;
      if (antes === 0) pos = novo.startsWith("(") ? 1 : 0;
      ref.current?.setSelectionRange(pos, pos);
    });
  }

  return (
    <input ref={ref} id={id} name={name} value={valor} onChange={mudar} required={required} autoComplete={autoComplete}
      inputMode="tel" type="tel" placeholder={placeholder} />
  );
}
