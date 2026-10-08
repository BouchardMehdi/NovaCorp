import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NovaCorp · Espace RH",
  description: "Plateforme interne de gestion des demandes RH NovaCorp.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="fr"><body>{children}</body></html>;
}
