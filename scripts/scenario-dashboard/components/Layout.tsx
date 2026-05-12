import { Head } from "$fresh/runtime.ts";

interface LayoutProps {
  title?: string;
  children: preact.ComponentChildren;
}

export default function Layout({ title, children }: LayoutProps) {
  return (
    <>
      <Head>
        <title>{title ? `${title} — Garazyk Scenarios` : "Garazyk Scenarios"}</title>
        <link rel="stylesheet" href="/tokens.css" />
        <link rel="stylesheet" href="/app.css" />
      </Head>
      <div class="app-layout">
        {children}
      </div>
    </>
  );
}
