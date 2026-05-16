/** Layout component — wraps pages with shared <head> and structure. @module Layout */
import { Head } from "$fresh/runtime.ts";

/** Props for the Layout wrapper component. */
interface LayoutProps {
  title?: string;
  children: preact.ComponentChildren;
}

/** Page layout shell with document head and app container. */
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
