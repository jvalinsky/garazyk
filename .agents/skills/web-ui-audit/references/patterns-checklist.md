# JavaScript and DOM Patterns Checklist

Use this checklist when reviewing frontend JavaScript structure and maintainability.

## Module Boundaries

- Keep code scoped to modules or closures; avoid unnecessary globals.
- Separate API calls, state updates, rendering, and event binding when practical.
- Keep selectors and DOM structure assumptions close to the components that use them.

## Event Handling

- Use `addEventListener` rather than inline handlers.
- Prefer event delegation for repeated dynamic elements.
- Avoid duplicate listeners after re-rendering or reconnecting views.
- Clean up timers, subscriptions, observers, and pending requests when views close.

## State and Errors

- Represent loading, empty, success, and error states explicitly.
- Keep user-visible errors specific and actionable.
- Avoid silent catch blocks and console-only failures for user-triggered actions.
- Ensure repeated actions are idempotent or guarded against double submission.
