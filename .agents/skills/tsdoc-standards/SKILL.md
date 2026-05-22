---
name: tsdoc-standards
description: Use when writing, reviewing, or linting TypeScript API documentation against this repository's TSDoc house standards.
---

# TSDoc House Standards

This project uses [TSDoc](https://tsdoc.org/) for code documentation. All public-facing TypeScript code must be documented according to these rules.

## Required Tags by Symbol Type

| Symbol Type | Required Tags |
| :--- | :--- |
| **Module** (file) | `@module <name>` on line 1 |
| **Class** | Description + `@remarks` (if complex) |
| **Method/Function** | Description + `@param <name>` - Description per parameter + `@returns` |
| **Interface/Type** | Description + property docs (see below) |
| **Generic** | `@typeParam <name> - Description` per type parameter |
| **Deprecated** | `@deprecated <reason> <alternative>` |
| **Error-throwing** | Description + `@throws` |
| **Public export** | `@public` / `@beta` / `@alpha` / `@internal` |

### Interface/Type property documentation

Every exported interface must have:
- A description on the interface itself explaining what it represents
- A `/** ... */` doc comment on each property, unless the property name is self-explanatory and the type makes the meaning unambiguous (e.g., `name: string` on a `NamedThing` interface)

For complex interfaces (5+ properties, nested types, or non-obvious semantics), add `@remarks` explaining constraints, invariants, or relationships between properties.

## Style Rules

- **Descriptions:** Use sentence fragments (no trailing period) for 1-liners, full sentences for multi-line.
- **Parameters:** Use the format `@param name - Description of parameter` (dash separator).
- **Type parameters:** Use the format `@typeParam T - Description of type parameter` (dash separator).
- **Examples:** Use the `@example` tag followed by a fenced code block with the `ts` language tag.
- **Cross-references:** Use `{@link ClassName}` or `{@link ClassName#method}` for inline references (no spaces inside braces). Use `@see` for "see also" lists.
- **Defaults:** Use `@defaultValue` for parameters/fields with default values.
- **Remarks:** Use `@remarks` for behavioral notes, edge cases, usage constraints, and implementation caveats — not just on classes, but on any symbol where the summary alone is insufficient.
- **Release tags:** Mark all exported symbols with `@public`, `@beta`, `@alpha`, or `@internal` to define API stability. `@internal` symbols are excluded from generated docs.
- **Deprecation:** Use `@deprecated Use {@link replacement} instead` — always include the replacement path.

## Enforcement

- Run `deno doc --lint <file>` to verify TSDoc syntax compliance.
- Run `deno task doc-lint` to lint the public Deno harness entry point.
- Run `deno task doc:ts-coverage` to report TypeScript documentation coverage for harness and dashboard exports.
- The project target is 90% documented exported TypeScript symbols. The CI baseline is intentionally lower and must be ratcheted upward as missing docs are fixed.
- All PRs are subject to documentation review against these standards.
- When TypeDoc validation is enabled, `validation.notDocumented` warnings must be resolved before merging.
