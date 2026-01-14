---
name: repo-stub-finder
description: Locate TODO/FIXME/stub patterns in this repository and summarize results.
---

# Repo Stub Finder

Use this skill to automatically identify placeholder or incomplete logic markers within the repository. It wraps the `scripts/stub_find.sh` helper that scans the target path for TODO/FIXME/stub strings.

## Workflow
1. Run `./scripts/stub_find.sh <path>` (defaults to the provided path, typically `.`).
2. Classify each match as:
   - **Logic stub**: guarded by TODO comments or returning placeholders (e.g., `return nil; // TODO`).
   - **Placeholder data**: fake responses for UI or tests (e.g., `result[@"decodingStatus"] = @"partial"`).
   - **Intentional temporary**: feature-flagged or noted by a story.
3. Report file paths and short rationales.
4. Ask for clarification or follow-up issues when a stub needs to be tracked.
