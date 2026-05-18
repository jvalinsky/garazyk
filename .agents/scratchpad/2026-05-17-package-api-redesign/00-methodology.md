# Package API Redesign Methodology

Date: 2026-05-17

## User Prompts

Initial review prompt:

> review apis of each package and think deeply about good api design in deno (use skills)

Implementation prompt:

> PLEASE IMPLEMENT THIS PLAN: Garazyk Package API Redesign And Deciduous Tracking

## Skills Used

- `using-deciduous`: graph nodes and scratchpad attachments.
- `better-code-opencode`: correctness, clarity, changeability, and primitive-first API design.
- `tsdoc-standards`: public TypeScript documentation and release tags.
- `refactor-opportunity-audit`: evidence-backed refactor planning and scratchpad conventions.
- `zod`: schema boundary and parse-don't-validate guidance.
- `garazyk-testing`: Deno package verification gates.

## Deciduous Nodes

- Goal: 12
- Decisions: 13, 14, 15, 16
- Actions: 17, 18, 19, 20, 21, 22, 23
- Outcomes: 24, 25, 26, 27, 28, 29, 30

## Attached Documents

- Goal 12: documents 2 and 3
- Decision 13: document 4
- Decision 14: document 5
- Decision 15: document 6
- Decision 16: document 7
- Actions 17-23: documents 8-14
- Outcomes 24-30: documents 15-21

## Evidence Commands

Current API inventory was gathered from:

- `deno doc --json packages/*/mod.ts`
- `deno doc --lint packages/laweta/mod.ts packages/gruszka/mod.ts packages/schemat/mod.ts packages/hamownia/mod.ts`
- `deno check packages/*/mod.ts`
- `deno task boundaries`
- `deno test -A packages/hamownia packages/schemat packages/gruszka packages/laweta`
- `deno check scripts/*.ts`
- `deno task dashboard:check`
- package `deno.json`, `mod.ts`, README files, and representative implementation modules

## Implementation Rule

Existing dirty worktree changes are user-owned. Work with current files and do not revert unrelated changes.
