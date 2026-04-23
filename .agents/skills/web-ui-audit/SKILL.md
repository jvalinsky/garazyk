---
name: web-ui-audit
description: "Comprehensive Web UI audit covering accessibility (a11y), code patterns, and security. Use when reviewing frontend code, ensuring WCAG compliance, or hardening web-based authentication flows."
---

# Web UI Audit

This master skill consolidates auditing for web accessibility, JavaScript patterns, and frontend security.

## Quick Start

Web UI audits in this repo are **manual and checklist-driven** — there is no scanner runner. Work through the three checklists in order:

1. **Review HTML/CSS** using the `web-ui-audit/references/accessibility-checklist.md`.
2. **Review JavaScript** using the `web-ui-audit/references/patterns-checklist.md`.
3. **Perform security audit** using the `web-ui-audit/references/security-checklist.md`.

## Audit Domains

### 1. Accessibility (a11y)
- **Goal**: Ensure WCAG 2.1 AA compliance.
- **Check**: Semantic HTML, ARIA labels, keyboard focus, and color contrast.
- **Fix**: Use native elements first; manage focus on dynamic content.

### 2. Code Patterns & Maintainability
- **Goal**: Maintain consistent ES6 module structure and clean DOM manipulation.
- **Check**: Module scoping, API client design, and event delegation.
- **Fix**: Avoid global pollution; use `addEventListener` instead of `onclick`.

### 3. Frontend Security
- **Goal**: Prevent XSS, CSRF, and sensitive data leakage.
- **Check**: `innerHTML` usage, token storage (avoid `localStorage` for sensitive tokens), and OAuth state validation.
- **Fix**: Use `textContent`, `sessionStorage` or httpOnly cookies, and PKCE.

## Resources
- **Checklists**: Consolidated in `web-ui-audit/references/` (no scripts — manual review only)
