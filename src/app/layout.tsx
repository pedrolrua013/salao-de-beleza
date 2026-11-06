import type { Metadata, Viewport } from "next";
import { cookies } from "next/headers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Belezando", template: "%s · Belezando" },
  description: "Agenda, WhatsApp, lembretes e gestão para salões de beleza.",
};
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#5B4BDB" };

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const tema = (await cookies()).get("tema")?.value;
  return (
    <html lang="pt-BR" data-theme={tema === "light" || tema === "dark" ? tema : undefined}>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;700&family=Sora:wght@500;600&display=swap"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
