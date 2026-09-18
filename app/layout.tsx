import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Evently — events worth showing up for",
  description: "Discover, organize and design invitations for memorable events.",
  other: {
    "codex-preview": "development",
  },
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body className="antialiased">{children}</body>
    </html>
  );
}
