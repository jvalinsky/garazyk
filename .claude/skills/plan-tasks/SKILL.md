---
name: plan-tasks
description: Generate an inline chat table of every remaining/open task in this repo's docs/plans/ (mega-plan, workstreams, phase-execution prompts), each rated by priority and codebase impact. Use whenever the user asks what's left in the plan, wants a roadmap/task status table, asks "what's next", asks about phase status, or wants to check progress on the mega plan or any workstream - even if they don't name this skill or docs/plans explicitly. Always re-reads the plan files fresh; never reuses a table from earlier in the conversation.
---

# Plan Tasks Table

Garazyk's planning lives entirely under `docs/plans/` — no other file in the
repo tracks backlog. This skill turns that prose into one scannable table so
the user doesn't have to re-read the mega plan and eight workstream files
every time they want a status check.

## Why re-read every time, never cache

The plan files change constantly — phases close, decisions land, new
regressions get filed as follow-ups. A table built from memory or from an
earlier turn in this conversation will silently drift from what the docs
actually say. Treat every invocation as a full recomputation: read the files
listed below fresh, even if you generated a table for this same repo minutes
ago.

## What to read, in this order

1. **`docs/plans/README.md`** — confirms the current document map and, most
   importantly, the precedence rule: *when a prompt and a workstream
   disagree, the workstream wins and the prompt gets corrected.* If you spot
   a conflict between a `prompts/phase-*.md` file and its workstream, trust
   the workstream and note the conflict in the table's impact column rather
   than silently picking one.
2. **`docs/plans/mega-plan.md`**, in full. This is the source of truth for
   repo-wide priority. Two sections matter most:
   - The **Priority model** table (boundary risk / structural drag / test
     leverage / change safety / payoff → Priority column). Reuse its
     Priority value verbatim for any item listed there instead of inventing
     your own rating.
   - The **Dependency order** phase list (Phase 0 through Phase 5) and its
     numbered items — this is usually the fastest way to see which phases
     are still open.
3. **Every file in `docs/plans/workstreams/*.md`**, in full. These carry the
   actual execution detail and the most current status prose (mega-plan
   entries can lag behind a workstream's own "Progress (date): ..." notes).
4. **Every file in `docs/plans/prompts/phase-*.md`** — read the YAML
   frontmatter (`phase`, `title`, `status`, `depends_on`) and any `## Blocked
   on` section. You don't need the full mission/scope prose unless a
   frontmatter status needs disambiguating against the workstream.
5. *(Optional corroboration, never authority)* If `deciduous` is available,
   `deciduous pulse` can surface something very recent that hasn't made it
   into the docs yet. If it disagrees with the docs, say so explicitly rather
   than quietly trusting whichever source looks newer — that discrepancy is
   itself useful information for the user.

If `docs/plans/prompts/` doesn't exist (the repo's own rules call for
deleting completed task plans and retiring prompts once a phase closes),
just skip step 4 and work from the mega plan and workstreams alone.

## What counts as "remaining"

A task belongs in the table if any of these are true:

- Its phase frontmatter status isn't `complete`.
- The workstream prose flags it with language like *not yet*, *remaining:*,
  *still open*, *still pending*, *own lane*, *follow-up*, *needs its own
  investigation*, *decision needed*, *blocked*, or *in progress*.
- A mega-plan numbered phase item doesn't carry a **Complete**/**Closed**
  prefix.
- The workstream explicitly calls out residual scope on an otherwise-closed
  item (e.g. "closes workstream 04... explicit remaining scope, not
  silently dropped" — that residual scope still belongs in the table even
  though the workstream itself is closed).

Leave out anything the docs mark Complete/Closed/Done, *unless* it falls
into that last bullet. Don't infer or invent tasks the docs don't state —
if you're unsure whether something counts, include it with a note in the
impact column rather than guessing silently in either direction. The user
would rather see a borderline item flagged than have it vanish.

## Rating priority

Use the mega-plan's own Priority Model values first (`P0`, `P1`, `P2`,
`Decided`, `Blocked: <reason>`) whenever the item appears in that table —
don't re-derive a rating the repo has already assigned.

For anything not in that table, reason it out in this order:

1. **Decision needed / Blocked (external)** — nothing to prioritize until
   someone outside the assistant decides or unblocks it. This ranks first
   regardless of technical severity, since no amount of engineering
   priority moves it forward.
2. **P0** — a security issue, a crash, a data-integrity risk, or anything
   blocking a stated gate from closing.
3. **P1** — protocol correctness or a phase's core, currently-scoped work.
4. **P2** — structural cleanup or a nice-to-have with nothing else blocked
   on it.

## Rating codebase impact

One short phrase, not a paragraph — enough for the user to judge whether it
matters to them right now. Aim for something that answers "why should I
care": what breaks if this stays unresolved, or what changes once it's
done. Examples of the right altitude:

- `AppView ingest data integrity`
- `blocks Phase 11 close (repo-wide lint baseline only)`
- `operator decision only, no code impact until decided`
- `test-only, no runtime impact`
- `protocol-compliance question, contradicts an interop fixture`

## Output format

Print exactly one markdown table directly in your chat response. Never
write it to a file, a scratchpad, or an artifact — the whole point is that
the user can see it without leaving the conversation, and a stale copy on
disk would just be one more thing to go out of date.

| Source | Task | Status | Priority | Codebase Impact |
| --- | --- | --- | --- | --- |
| Phase 9 / WS06 P6.3 | App attestation for `managing-app` | Decision needed | Decision needed | Operator decision only, no code impact until decided |
| Phase 12 / WS02 A3 | Objective-C god-file decomposition | Not started | P2 | Structural only; no gate blocked |

(The rows above are illustrative of the format, not a cached result —
always replace them with what you actually find.)

After the table, close with 1-2 sentences: name which items are waiting on
a human decision specifically (so the user knows those won't move without
their input), and name the single next unblocked, actionable item in phase
order. That's usually the most useful sentence in the whole response — it's
the answer to "so what do I actually do next."
