import type { MetadataRoute } from "next";

/** Permite "Adicionar à tela inicial": a equipe abre a agenda e o extrato como um app, sem loja. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Belezando",
    short_name: "Belezando",
    description: "Agenda, comanda, comissão e WhatsApp para salões de beleza.",
    start_url: "/hoje",
    display: "standalone",
    background_color: "#F7F7FA",
    theme_color: "#5B4BDB",
    lang: "pt-BR",
    icons: [
      { src: "/icone.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icone.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
