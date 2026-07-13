// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

(() => {
  const navigation = document.querySelectorAll(".demo-nav-link");
  const sections = document.querySelectorAll(".demo-section");
  const viewport = document.querySelector(".demo-viewport");
  const themeToggle = document.getElementById("demo-theme-toggle");
  const themeLabel = document.querySelector(".demo-theme-label");

  function showScreen(screen) {
    sections.forEach((section) => {
      const isActive = section.id === screen;
      section.classList.toggle("active", isActive);
      section.setAttribute("aria-hidden", String(!isActive));
    });

    navigation.forEach((link) => {
      const isActive = link.dataset.screen === screen;
      link.classList.toggle("active", isActive);
      if (isActive) {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    });

    if (viewport) {
      viewport.scrollTop = 0;
    }
  }

  function savedTheme() {
    try {
      return globalThis.localStorage.getItem("garazyk-demo-theme");
    } catch (_) {
      return null;
    }
  }

  function persistTheme(theme) {
    try {
      globalThis.localStorage.setItem("garazyk-demo-theme", theme);
    } catch (_) {
      // file:// previews can have storage disabled; the selected theme still applies.
    }
  }

  function applyTheme(theme, shouldPersist) {
    const dark = theme === "dark";
    document.documentElement.dataset.demoTheme = dark ? "dark" : "light";
    document.documentElement.style.colorScheme = dark ? "dark" : "light";

    if (themeToggle) {
      themeToggle.setAttribute("aria-pressed", String(dark));
      themeToggle.setAttribute(
        "aria-label",
        dark ? "Switch to light appearance" : "Switch to dark appearance",
      );
    }

    if (themeLabel) {
      themeLabel.textContent = dark ? "Light" : "Dark";
    }

    if (shouldPersist) {
      persistTheme(theme);
    }
  }

  navigation.forEach((link) => {
    link.addEventListener("click", () => showScreen(link.dataset.screen));
  });

  if (themeToggle) {
    themeToggle.addEventListener("click", () => {
      const nextTheme = document.documentElement.dataset.demoTheme === "dark"
        ? "light"
        : "dark";
      applyTheme(nextTheme, true);
    });
  }

  const initialTheme = savedTheme() || (
    globalThis.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light"
  );
  applyTheme(initialTheme, false);
})();
