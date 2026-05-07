# Session Completion Workflow

This workflow must be executed at the end of every work session before closing the CLI.

## Steps

1. **Verify Quality Gates**: Run the `quality_gates.md` workflow.
2. **Synchronize Decision Graph**: Run `deciduous sync`.
3. **Commit and Push**:
   ```bash
   git pull --rebase
   git push
   ```
4. **Verify Remote Status**: Run `git status` to ensure the local branch is up to date with origin.
5. **Future Work**: File GitHub issues for any remaining tasks or identified technical debt.

## Exit Criteria
- `git status` shows "Your branch is up to date with 'origin/main'".
- No pending `deciduous` nodes left in `in_progress` state for completed work.
