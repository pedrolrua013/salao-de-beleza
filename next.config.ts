import type { NextConfig } from "next";

const producao = process.env.NODE_ENV === "production";
// Política de conteúdo: só o próprio site, o Supabase e as fontes do Google. 'unsafe-inline' é necessário pelos scripts e estilos do Next.
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${producao ? "" : " 'unsafe-eval'"}`,
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: blob: https://*.supabase.co",
  "connect-src 'self' https://*.supabase.co https://viacep.com.br https://brasilapi.com.br", // busca de CEP no cadastro
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join("; ");

const config: NextConfig = {
  poweredByHeader: false,
  output: "standalone", // gera um servidor mínimo, usado pela imagem Docker
  experimental: { serverActions: { bodySizeLimit: "6mb" } }, // fotos de até 5 MB na ficha da cliente
  async headers() {
    return [{
      // Links pessoais da cliente (horário, ficha, pagamento, termo, avaliação, área): nunca no Google.
      source: "/s/:slug/:tipo/:token*",
      headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }, { key: "Cache-Control", value: "private, no-store" }],
    }, {
      source: "/:path*",
      headers: [
        { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
        { key: "Content-Security-Policy", value: csp },
        { key: "X-Content-Type-Options", value: "nosniff" },
        { key: "X-Frame-Options", value: "DENY" },
        { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
      ],
    }];
  },
};

export default config;
