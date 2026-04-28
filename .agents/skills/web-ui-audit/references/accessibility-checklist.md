# Accessibility Checklist

Use this checklist when reviewing HTML and CSS in `AdminUI/` or other web assets.

## Semantics

- Prefer native controls and landmarks before ARIA.
- Ensure headings form a useful hierarchy.
- Associate labels with form controls.
- Give images meaningful `alt` text, or empty `alt` text for decorative images.

## Keyboard and Focus

- All interactive elements are reachable by keyboard.
- Focus order follows visual and workflow order.
- Visible focus indicators are not removed or hidden.
- Modals, drawers, menus, and dynamic panels manage focus explicitly.

## Visual Access

- Text and UI controls meet WCAG 2.1 AA contrast expectations.
- Layout works at common zoom levels and narrow widths.
- Status, errors, and validation states are not conveyed by color alone.
- Motion is limited or respects reduced-motion preferences where relevant.
