/** Mobile bottom navigation and drawer for scenarios, network, and topology. @module MobileNav */
import { useEffect, useRef } from "preact/hooks";
import { useRuntime } from "../runtime.ts";
import type { MobileNavPanel } from "../dashboard_state.ts";
import SidebarPanels from "./SidebarPanels.tsx";

interface MobileNavProps {
  activeScenario?: string;
}

const PANEL_LABELS: Record<MobileNavPanel, string> = {
  scenarios: "Scenarios",
  network: "Network",
  topology: "Topology",
};

/** Bottom tab bar and slide-up drawer for narrow viewports. */
export default function MobileNav({ activeScenario }: MobileNavProps) {
  const { state, dispatch } = useRuntime();
  const panel = state.value.ux.mobileNavPanel;
  const drawerRef = useRef<HTMLDivElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!panel) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        dispatch({ type: "ux/closeMobileNav" });
      }
    };

    globalThis.addEventListener("keydown", onKeyDown);
    closeButtonRef.current?.focus();

    return () => globalThis.removeEventListener("keydown", onKeyDown);
  }, [panel]);

  useEffect(() => {
    if (panel) {
      document.documentElement.classList.add("mobile-drawer-open");
    } else {
      document.documentElement.classList.remove("mobile-drawer-open");
    }
    return () => document.documentElement.classList.remove("mobile-drawer-open");
  }, [panel]);

  function toggle(panelId: MobileNavPanel) {
    dispatch({ type: "ux/toggleMobileNav", panel: panelId });
  }

  function close() {
    dispatch({ type: "ux/closeMobileNav" });
  }

  return (
    <>
      <nav class="mobile-nav-bar" aria-label="Mobile navigation">
        {(Object.keys(PANEL_LABELS) as MobileNavPanel[]).map((id) => (
          <button
            key={id}
            type="button"
            class={`mobile-nav-tab ${panel === id ? "mobile-nav-tab--active" : ""}`}
            aria-expanded={panel === id}
            aria-controls={panel === id ? "mobile-nav-drawer" : undefined}
            onClick={() => toggle(id)}
          >
            {PANEL_LABELS[id]}
          </button>
        ))}
      </nav>

      {panel && (
        <>
          <button
            type="button"
            class="mobile-drawer-backdrop"
            aria-label="Close navigation"
            onClick={close}
          />
          <div
            ref={drawerRef}
            id="mobile-nav-drawer"
            class="mobile-drawer"
            role="dialog"
            aria-modal="true"
            aria-labelledby="mobile-drawer-title"
          >
            <header class="mobile-drawer-header">
              <h2 id="mobile-drawer-title" class="mobile-drawer-title">
                {PANEL_LABELS[panel]}
              </h2>
              <button
                ref={closeButtonRef}
                type="button"
                class="btn btn-secondary btn-sm"
                onClick={close}
              >
                Close
              </button>
            </header>
            <div class="mobile-drawer-body">
              <SidebarPanels
                view={panel}
                activeScenario={activeScenario}
                onNavigate={close}
              />
            </div>
          </div>
        </>
      )}
    </>
  );
}
