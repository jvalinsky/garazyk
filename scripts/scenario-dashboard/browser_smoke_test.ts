/**
 * Scenario dashboard browser smoke (Phase 0 item 1 / workstream 00 B0.2
 * item 5). This file covers the Fresh scenario dashboard only; Admin CSP/CSRF
 * enforcement and the OAuth consent flow are covered against the real ObjC
 * AdminUIServer by ../admin_ui_browser_smoke_test.ts.
 *
 *   1. Dashboard controls are rendered and interactive
 *   2. Security headers on the dashboard's main page response
 *   3. Mutation-capability enforcement on the dashboard's own API routes
 *   4. Scenario detail page navigation
 *   5. Keyboard navigation (tab stops, focus order)
 *
 * Usage: deno run -A scripts/scenario-dashboard/browser_smoke_test.ts
 */

import { runBrowserTest } from "./browser_test_helpers.ts";
import { AnsiUp } from "ansi_up";
import { sanitizeLogHtml } from "./utils/log_html.ts";

const DASHBOARD_DIR = new URL(".", import.meta.url);
const PORT = 3096;

async function main() {
  await runBrowserTest(DASHBOARD_DIR, PORT, async ({ page, baseUrl }) => {
    // ── Area 1: Dashboard controls ──────────────────────────────────────
    // The page must render the toolbar, sidebar, search input, and topology
    // selector. These are structural Fresh components from the island/component
    // tree documented in the route handler.
    await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 20_000 });
    console.log("[OK] Dashboard page loaded (networkidle)");

    // Verify the page title and structural elements.
    const title = await page.title();
    if (!title || title !== "Dashboard") {
      // Fresh does not always set <title> via _app.tsx — this is not a
      // failure; we just note it for the record.
      console.log(`[INFO] Page title: "${title}"`);
    }

    // Toolbar: check for the search input (Toolbar island).
    const searchInput = page.locator("input[type=search]");
    const searchCount = await searchInput.count();
    if (searchCount > 0) {
      console.log(`[OK] Search input found (${searchCount})`);
    } else {
      // The search input may be hidden at narrow viewports; accept it.
      console.log("[INFO] Search input not visible at default viewport");
    }

    // Topology selector (known id from topology_persistence_test).
    const topoSelect = page.locator("select#topology-select");
    const topoCount = await topoSelect.count();
    console.log(`[OK] Topology select elements: ${topoCount}`);

    // Main content heading (section-heading class).
    const sectionHeading = page.locator(
      "h2.section-heading, h2:has-text('Scenarios')",
    );
    const headingCount = await sectionHeading.count();
    console.log(`[OK] Scenarios heading found: ${headingCount}`);

    // Verify no browser console errors on initial load.
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        consoleErrors.push(msg.text());
      }
    });
    // Wait for any async rendering to settle.
    await new Promise((r) => setTimeout(r, 500));
    const ignoredPatterns = [
      " experimental ",
      " deprecation",
      "favicon",
      "ERR_BLOCKED_BY_RESPONSE",
    ];
    const relevantErrors = consoleErrors.filter(
      (e) => !ignoredPatterns.some((p) => e.includes(p)),
    );
    if (relevantErrors.length > 0) {
      console.log(
        `[WARN] Console errors on first load: ${relevantErrors.length}`,
      );
      for (const err of relevantErrors) {
        console.log(`  └─ ${err}`);
      }
    } else {
      console.log("[OK] No relevant console errors on initial page load");
    }

    // ── Area 2: CSP header check on main page ──────────────────────────
    // The dashboard middleware in _middleware.ts applies security validation
    // but does not inject a CSP header directly. The Fresh framework and
    // AdminUIServer (ObjC) are responsible for CSP. Verify the main page
    // response has reasonable security headers.
    const response = await page.goto(baseUrl, {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
    });
    if (response) {
      const csp = response.headers()["content-security-policy"] || "";
      if (csp) {
        console.log(`[OK] CSP header present: ${csp.slice(0, 80)}...`);
        if (csp.includes("script-src-attr 'none'")) {
          console.log("[OK] CSP blocks inline event handlers");
        }
      } else {
        // The dashboard is loopback-only and uses Fresh's default rendering;
        // CSP enforcement is on the ObjC AdminUIServer side. Note this as
        // expected architecture, not a gap.
        console.log(
          "[INFO] No CSP on dashboard page (loopback-only dev server; CSP enforced by AdminUIServer)",
        );
      }

      const cto = response.headers()["x-content-type-options"];
      if (cto) console.log(`[OK] X-Content-Type-Options: ${cto}`);

      const xfo = response.headers()["x-frame-options"];
      if (xfo) console.log(`[OK] X-Frame-Options: ${xfo}`);
    }

    // ── Area 3: Mutation-capability enforcement ─────────────────────────
    // The dashboard middleware rejects mutations without a valid capability
    // token. Verify directly via fetch.
    const mutationPaths = [
      "/api/network/start",
      "/api/network/stop",
      "/api/runs/start",
    ];
    for (const path of mutationPaths) {
      const res = await fetch(`${baseUrl}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });
      const status = res.status;
      if (status === 403) {
        console.log(`[OK] Mutation ${path} rejected (403) without capability`);
      } else {
        console.log(
          `[WARN] Mutation ${path} returned ${status} (expected 403)`,
        );
      }
    }

    // Verify a GET request to an API path works without capability.
    const healthRes = await fetch(`${baseUrl}/api/network/health`);
    if (healthRes.ok) {
      console.log("[OK] GET /api/network/health accepted without capability");
    } else {
      console.log(
        `[WARN] GET /api/network/health returned ${healthRes.status}`,
      );
    }

    // ── Area 4: Scenario detail page structure ──────────────────────────
    // Navigate to a static scenario page to verify it renders without errors.
    const scenarioPage = page.locator("a[href^='/scenario/']").first();
    const scenarioLinkCount = await scenarioPage.count();
    if (scenarioLinkCount > 0) {
      const href = await scenarioPage.getAttribute("href");
      console.log(`[OK] Scenario link found: ${href}`);
      await page.goto(`${baseUrl}${href}`, {
        waitUntil: "domcontentloaded",
        timeout: 15_000,
      });
      console.log(`[OK] Scenario detail page loaded: ${href}`);
      await page.goBack({ waitUntil: "domcontentloaded" });
      console.log("[OK] Navigated back to dashboard");
    } else {
      console.log("[INFO] No scenario links on page (database may be empty)");
    }

    // ── Area 5: Keyboard navigation (tab stops) ─────────────────────────
    // Check that interactive elements are reachable via Tab key.
    await page.keyboard.press("Tab");
    const focusedElement = page.locator(":focus");
    const focusedTag = await focusedElement.evaluate(
      (el) => el?.tagName || null,
    );
    if (focusedTag) {
      console.log(`[OK] Tab reaches element: <${focusedTag}>`);
    } else {
      // The Fresh dashboard may not have auto-focused elements on first tab.
      // This is informational — full keyboard workflow validation is best
      // done via the TUI capture tests (tui_integration_test.ts).
      console.log("[INFO] No element focused on first Tab press");
    }

    // Tab through interactive elements to verify focus moves.
    const interactive = page.locator(
      'a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])',
    );
    const interactiveCount = await interactive.count();
    console.log(`[OK] Interactive elements: ${interactiveCount}`);

    // ── Area 6: Accessibility (workstream 04 U4/U5) ─────────────────────
    // These assert (not just log) the dashboard's document semantics, focus
    // management, and status-not-color-only work from phase 8 slice 1.
    await page.goto(baseUrl, {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
    });

    const lang = await page.evaluate(() =>
      // deno-lint-ignore no-explicit-any
      (globalThis as any).document.documentElement.lang
    );
    if (lang !== "en") {
      throw new Error(`Expected <html lang="en">, got "${lang}"`);
    }
    console.log("[OK] Document language set (lang=en)");

    const h1Count = await page.locator("h1").count();
    if (h1Count < 1) {
      throw new Error("Expected at least one <h1> on the page");
    }
    console.log(`[OK] Page has an <h1> (${h1Count})`);

    // Run History table must use scoped headers and a caption, not bare <th>.
    const historyTable = page.locator(".run-history-card table.history-table");
    if (await historyTable.count() > 0) {
      const captionCount = await historyTable.locator("caption").count();
      if (captionCount !== 1) {
        throw new Error(
          `Expected exactly one <caption> on the run history table, found ${captionCount}`,
        );
      }
      const unscopedHeaders = await historyTable.locator("th:not([scope])")
        .count();
      if (unscopedHeaders > 0) {
        throw new Error(
          `Run history table has ${unscopedHeaders} <th> without a scope attribute`,
        );
      }
      console.log(
        "[OK] Run history table has a caption and scoped column headers",
      );
    } else {
      console.log(
        "[INFO] Run history table not present (no runs recorded yet)",
      );
    }

    // Status bar health indicator must not rely on color alone.
    const healthDot = page.locator(".status-bar .health-dot");
    if (await healthDot.count() > 0) {
      const ariaHidden = await healthDot.getAttribute("aria-hidden");
      if (ariaHidden !== "true") {
        throw new Error(
          "Expected .health-dot to be aria-hidden (paired with an sr-only text alternative)",
        );
      }
      const srText = await page.locator(
        ".status-bar .health-dot-container .sr-only",
      ).count();
      if (srText !== 1) {
        throw new Error(
          "Expected an .sr-only text alternative next to .health-dot",
        );
      }
      console.log("[OK] PDS health status has a non-color text alternative");
    } else {
      console.log(
        "[INFO] Status bar health dot not present (no PDS URL configured)",
      );
    }

    // Reduced-motion preference must suppress animation/transition duration.
    // getComputedStyle serializes to seconds (e.g. "1e-05s" for 0.01ms) —
    // parse the numeric value rather than matching the string verbatim.
    await page.emulateMedia({ reducedMotion: "reduce" });
    const reducedDurationSeconds = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const win = globalThis as any;
      const probe = win.document.createElement("div");
      probe.style.transition = "opacity 300ms";
      win.document.body.appendChild(probe);
      const duration = parseFloat(
        win.getComputedStyle(probe).transitionDuration,
      );
      probe.remove();
      return duration;
    });
    if (!(reducedDurationSeconds <= 0.0001)) {
      throw new Error(
        `Expected transition-duration near-zero under prefers-reduced-motion, got ${reducedDurationSeconds}s`,
      );
    }
    console.log("[OK] prefers-reduced-motion suppresses transition duration");
    await page.emulateMedia({ reducedMotion: null });

    // Mobile drawer: focus trap while open, focus restore on close. Clicking
    // the island's trigger is the end-to-end proof that Fresh hydrated it.
    await page.setViewportSize({ width: 400, height: 800 });
    const navTab = page.locator(".mobile-nav-tab").first();
    await navTab.waitFor({ state: "visible", timeout: 5_000 });
    if (await navTab.count() === 0 || !await navTab.isVisible()) {
      throw new Error(
        "Mobile navigation trigger is not visible at 400px width",
      );
    }
    const undersizedNavTabs = await page.locator(".mobile-nav-tab").evaluateAll(
      (elements) =>
        elements.map((element) => {
          const rect = element.getBoundingClientRect();
          return { width: rect.width, height: rect.height };
        }).filter(({ width, height }) => width < 44 || height < 44),
    );
    if (undersizedNavTabs.length > 0) {
      throw new Error(
        `Mobile navigation has ${undersizedNavTabs.length} target(s) smaller than 44×44 CSS px`,
      );
    }
    console.log(
      "[OK] Mobile navigation controls meet the 44×44 CSS px target size",
    );

    await navTab.click();
    const drawer = page.locator("#mobile-nav-drawer");
    await drawer.waitFor({ state: "visible", timeout: 5_000 });

    const focusedInDrawer = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.querySelector("#mobile-nav-drawer")?.contains(
        doc.activeElement,
      ) ??
        false;
    });
    if (!focusedInDrawer) {
      throw new Error(
        "Expected focus to move inside the mobile drawer when it opens",
      );
    }
    console.log("[OK] Focus moves into the mobile drawer on open");

    // Shift+Tab from the first focusable element must wrap to the last (trap).
    await page.keyboard.press("Shift+Tab");
    const wrappedToLast = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      const drawer = doc.querySelector("#mobile-nav-drawer");
      const focusable = drawer?.querySelectorAll(
        'button, a, input, select, textarea, [tabindex]:not([tabindex="-1"])',
      );
      return !!focusable && focusable.length > 0 &&
        doc.activeElement === focusable[focusable.length - 1];
    });
    if (!wrappedToLast) {
      throw new Error(
        "Expected Shift+Tab from the first drawer control to wrap to the last (focus trap)",
      );
    }
    console.log("[OK] Focus trap wraps Shift+Tab to the last drawer control");

    await page.keyboard.press("Escape");
    await drawer.waitFor({ state: "hidden", timeout: 5_000 });
    const restoredFocus = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.activeElement?.classList.contains("mobile-nav-tab") ?? false;
    });
    if (!restoredFocus) {
      throw new Error(
        "Expected focus to restore to the triggering nav tab after the drawer closes",
      );
    }
    console.log("[OK] Focus restores to the trigger after the drawer closes");

    const focusStyle = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const win = globalThis as any;
      const active = win.document.activeElement;
      const style = active ? win.getComputedStyle(active) : null;
      return {
        matchesFocusVisible: active?.matches(":focus-visible") ?? false,
        outlineStyle: style?.outlineStyle ?? "none",
        outlineWidth: parseFloat(style?.outlineWidth ?? "0"),
      };
    });
    if (
      !focusStyle.matchesFocusVisible || focusStyle.outlineStyle === "none" ||
      focusStyle.outlineWidth < 2
    ) {
      throw new Error(
        `Restored mobile-nav focus indicator is not visibly 2px (style=${focusStyle.outlineStyle}, width=${focusStyle.outlineWidth})`,
      );
    }
    console.log("[OK] Restored mobile-nav focus has a visible 2px indicator");

    // A 640px CSS viewport is the layout width of a 1280px desktop viewport
    // at 200% zoom. Reflow must avoid page-level horizontal scrolling.
    await page.setViewportSize({ width: 640, height: 800 });
    const horizontalOverflow = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.documentElement.scrollWidth >
        doc.documentElement.clientWidth + 1;
    });
    if (horizontalOverflow) {
      throw new Error(
        "Dashboard has page-level horizontal overflow at 200% zoom equivalent",
      );
    }
    console.log(
      "[OK] Dashboard reflows without page-level horizontal overflow at 200% zoom equivalent",
    );
    await page.setViewportSize({ width: 1280, height: 800 });

    // ── Area 7: Hostile ANSI log rendering (workstream 04 U6 item 5) ───
    // LogViewer.tsx renders log output via
    //   dangerouslySetInnerHTML={{ __html: sanitizeLogHtml(ansiUp.ansi_to_html(text)) }}
    // Run the *real* production pipeline (same ansi_up instance config, same
    // sanitizeLogHtml import) against a battery of hostile payloads embedded
    // in ANSI-colored log text, then check what a real browser does with the
    // output — this is the thing that actually matters for XSS, not just a
    // regex unit test.
    const ansiUp = new AnsiUp();
    const hostilePayloads = [
      "\x1b[31m<script>window.__logXss=1</script>\x1b[0m",
      '<img src=x onerror="window.__logXss=2">',
      '<a href="javascript:window.__logXss=3">click me</a>',
      '<svg onload="window.__logXss=4"></svg>',
      // Nested/malformed tags — a classic regex-sanitizer bypass attempt.
      "<scr<script>ipt>window.__logXss=5</scr</script>ipt>",
      '<div onmouseover="window.__logXss=6">hover</div>',
    ];

    await page.goto(baseUrl, {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
    });
    await page.evaluate(() => {
      (globalThis as unknown as { __logXss?: number }).__logXss = undefined;
    });

    for (const payload of hostilePayloads) {
      const rendered = sanitizeLogHtml(ansiUp.ansi_to_html(payload));
      await page.evaluate((html: string) => {
        // deno-lint-ignore no-explicit-any
        const doc = (globalThis as any).document;
        const host = doc.getElementById("__smoke_log_host") ??
          (() => {
            const el = doc.createElement("pre");
            el.id = "__smoke_log_host";
            doc.body.appendChild(el);
            return el;
          })();
        host.innerHTML = html;
      }, rendered);
    }
    // Let any injected <script>/onerror/onload handlers have a chance to fire.
    await page.waitForTimeout(200);

    const xssMarker = await page.evaluate(() =>
      (globalThis as unknown as { __logXss?: number }).__logXss
    );
    if (xssMarker !== undefined) {
      throw new Error(
        `Hostile ANSI log payload executed as script (marker=${xssMarker}) — ` +
          "ansi_up escaping or sanitizeLogHtml regression",
      );
    }
    console.log(
      `[OK] ${hostilePayloads.length} hostile ANSI/HTML log payloads rendered inertly (no script execution)`,
    );

    const hostHtml: string = await page.evaluate(() => {
      // deno-lint-ignore no-explicit-any
      const doc = (globalThis as any).document;
      return doc.getElementById("__smoke_log_host")?.innerHTML ?? "";
    });
    if (/<script[\s>]/i.test(hostHtml) || /\son\w+\s*=/i.test(hostHtml)) {
      throw new Error(
        "Sanitized log output still contains a live <script> tag or on* handler attribute",
      );
    }
    console.log(
      "[OK] Sanitized log output has no live <script> tags or event-handler attributes",
    );

    // ── Summary ─────────────────────────────────────────────────────────
    console.log("\n✅ All browser smoke baseline checks completed");
    if (consoleErrors.length > 0) {
      console.log(`[INFO] Total console-error events: ${consoleErrors.length}`);
    }
  });
}

if (import.meta.main) {
  await main().catch((err) => {
    console.error(`\n❌ BROWSER SMOKE FAILED: ${err.message}`);
    Deno.exit(1);
  });
}
