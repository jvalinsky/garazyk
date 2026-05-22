# Documentation Review Backlog

Date: 2026-05-22

| Priority | Path | Status | Proposed change | Risk | Evidence scratchpad |
| --- | --- | --- | --- | --- | --- |
| P0 | `README.md` | Update | Replace root `docker compose up` with current local-network command or explicit compose file. | High: first-run instructions fail. | `scratchpads/docs-review-findings.md` |
| P0 | `docs/01-getting-started/setup.md` | Update | Same Docker startup correction as README. | High: setup guide sends users to nonexistent root Compose file. | `scratchpads/docs-review-findings.md` |
| P0 | `docs/20-explanation/guides/DEPLOYMENT.md` | Update | Distinguish local dev compose, single-PDS compose, and production deployment. | High: deployment docs can cause operator mistakes. | `scratchpads/docs-review-findings.md` |
| P0 | `.agents/agents/pr-reviewer.md` | Update | Remove/fix broken `.opencode/workflows/pull_request_review_workflow.md` link. | Medium: agent workflow reference is broken. | `scratchpads/docs-review-findings.md` |
| P0 | `objc-jupyter-wasm/docs/plans/master-runtime-plan.md` | Update | Fix four scratchpad links; clarify historical/completed status. | Medium: broken links and stale timeline. | `scratchpads/docs-review-findings.md` |
| P1 | `.agents/skills/researcher-hand-skill/SKILL.md` | Update | Replace placeholder `url` markdown links with real URLs or plain text. | Low/medium: link checker noise, poor source citation guidance. | `scratchpads/docs-review-findings.md` |
| P1 | `docs/plans/deno-packages-next-steps.md` | Archive/merge | Mark as superseded by `docs/plans/next-steps.md` or move to archive. | Medium: stale plan conflicts with active plan. | `scratchpads/docs-review-findings.md` |
| P1 | `docs/plans/tsdoc-revision-plan.md` | Archive/merge | Same as above. Preserve any unique context in `next-steps.md`. | Medium: stale TSDoc roadmap can misdirect work. | `scratchpads/docs-review-findings.md` |
| P1 | `docs/documentation_remediation_plan.md` | Archive/update | Convert from active plan to completed remediation postmortem, or archive. | Medium: plan says to do work already marked complete elsewhere. | `scratchpads/docs-review-findings.md` |
| P1 | `Garazyk/Sources/Admin/ADMINUI_DELIVERY_SUMMARY.md` | Archive/merge | Move to historical record or merge unique details into canonical Admin UI doc. | Medium: dated completion docs may be mistaken for current status. | `scratchpads/docs-review-findings.md` |
| P1 | `Garazyk/Sources/Admin/ADMINUI_INTEGRATION_COMPLETE.md` | Archive/merge | Same as above; verify auth/static asset claims against current code first. | Medium: current AdminUIServer split may differ. | `scratchpads/docs-review-findings.md` |
| P1 | `objc-jupyter-wasm/docs/plans/obsolete-revised-plan.txt` | Delete/archive | Confirm unique unresolved items, then delete or move to archive. | Low: explicitly obsolete, but may contain historical context. | `scratchpads/docs-review-findings.md` |
| P2 | `scripts/scenarios/README.md` | Update | Add explicit data-loss warning for teardown if volumes/data are removed. | Medium if teardown deletes local state; low otherwise. | `scratchpads/docs-review-findings.md` |
| P2 | `scratchpads/**`, `.agents/scratchpad/**`, `.opencode/scratch/**` | Policy | Define retention/visibility policy and exclude from canonical docs checks by default. | Low: mostly audit noise unless indexed as canonical docs. | `scratchpads/docs-review-inventory.md` |

## Suggested execution batches

1. **Broken-link batch:** fix `.agents/agents/pr-reviewer.md`, researcher-hand-skill placeholders, and WASM plan links.
2. **Onboarding command batch:** update README/setup/deployment Docker commands together.
3. **Archive-plan batch:** move or relabel superseded planning docs after owner confirmation.
4. **Admin UI doc consolidation batch:** choose canonical current Admin UI docs, then archive dated delivery notes.
5. **Policy batch:** document which scratchpad/report trees are excluded from docs audits and which scratchpads must be linked from deciduous.
