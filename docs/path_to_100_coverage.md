# Roadmap to 100% Documentation Coverage

## Executive Summary

This document outlines the systematic path to achieving 100% documentation coverage across the
Garazyk codebase. Currently at 77%, the project requires a disciplined approach to bridge the gap in
`Core`, `Services`, and `Blob` subsystems.

## Phase 1: Hardening the CI Gate (Immediate)

Before scaling, we must prevent regression.

- [ ] **Enforce Coverage Gates:** Update CI pipelines to use `scripts/docs/doc-coverage.ts` to block
      PRs that reduce coverage.
- [ ] **Subsystem Thresholds:** Implement mandatory minimums in CI:
  - `Database`: 100%
  - `AdminUIServer`: 100%
  - `Chat`: 100%
  - `AppView`: 90%
  - `Blob`: 80%
  - `Services`: 80%
  - `Core`: 80%

## Phase 2: Systematic Subsystem Sprints

We will tackle documentation in order of deficit and architectural criticality.

### Sprint 1: Services & Blob (Goal: 90%)

- **Target:** `Services` (84%) and `Blob` (93%).
- **Focus:** Undocumented Protocols, Enums, and delegate interfaces.
- **Status:** Blob (93%) and Services (84%) subsystems have surpassed the 80% CI gate requirement.
  Focus now shifting to `Core` (63%).

### Sprint 2: Core Infrastructure (Goal: 85%)

- **Target:** `Core` (63%).
- **Focus:** Complex headers, internal-facing APIs, and trait/utility classes.

### Sprint 3: The "Other" Cleanup (Goal: 90%)

- **Target:** `Other` (78%).
- **Focus:** Map remaining uncategorized files to appropriate subsystems or merge them into logical
  `Core` modules.

## Phase 3: The Final Push to 100%

Once subsystems reach >90% coverage:

- [ ] **Doxygen Compliance Check:** Run comprehensive `doxygen` audit to surface hidden warnings
      (graph-size issues, orphaned tags).
- [ ] **Peer Review Audit:** Perform a manual review of critical API documentation to ensure clarity
      and contractual accuracy.
- [ ] **Documentation-as-Code:** Introduce `doc-coverage` as a standard PR check for all modified
      headers.

## Tracking & Accountability

- **Weekly Audit:** `deno task doc:coverage` results to be posted to the internal team channel.
- **Skill Utilization:** Force `rewriting-code-comments` skill usage on any header modification PRs.
- **Doxygen Warnings:** Maintain a strictly monitored log of `docs/api/doxygen-warnings.log`, with a
  target of **zero** warnings.
