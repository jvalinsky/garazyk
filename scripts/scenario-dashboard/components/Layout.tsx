/** Layout component — wraps pages with shared <head> and structure. @module Layout */
import { Head } from "$fresh/runtime.ts";

/** Props for the Layout wrapper component. */
interface LayoutProps {
  title?: string;
  /** When true, the page renders its own visible h1 and the layout skips the sr-only fallback. */
  hasOwnH1?: boolean;
  children: preact.ComponentChildren;
}

/** Page layout shell with document head and app container. */
export default function Layout({ title, hasOwnH1, children }: LayoutProps) {
  return (
    <>
      <Head>
        <title>
          {title ? `${title} — Garazyk Scenarios` : "Garazyk Scenarios"}
        </title>
        <link rel="stylesheet" href="/tokens.css" />
        <link rel="stylesheet" href="/app.css" />
      </Head>
      {!hasOwnH1 && <h1 class="sr-only">{title ?? "Garazyk Scenarios"}</h1>}
      <div class="app-layout">
        {children}
      </div>
    </>
  );
}
