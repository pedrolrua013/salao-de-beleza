"use client";

/** Alterna entre claro e escuro. A escolha fica num cookie para o servidor já entregar a página no tema certo, sem piscar.
 *  Enquanto a pessoa não escolher, vale o tema do aparelho. O ícone e o texto trocam por CSS, sem esperar o JavaScript. */
export function AlternarTema() {
  function alternar() {
    const raiz = document.documentElement;
    const escuroAgora = raiz.dataset.theme ? raiz.dataset.theme === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    const proximo = escuroAgora ? "light" : "dark";
    raiz.classList.add("tema-troca");
    raiz.dataset.theme = proximo;
    document.cookie = `tema=${proximo}; path=/; max-age=31536000; SameSite=Lax`;
    window.setTimeout(() => raiz.classList.remove("tema-troca"), 400);
  }
  return (
    <button type="button" className="tema-bt" onClick={alternar}>
      <svg className="tema-lua" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.500a8.5 8.5 0 1 0 11 11z" /></svg>
      <svg className="tema-sol" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></svg>
      <span><span className="tema-t-escuro">Modo escuro</span><span className="tema-t-claro">Modo claro</span></span>
    </button>
  );
}
