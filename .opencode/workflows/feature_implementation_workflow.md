# Feature Implementation Workflow

This workflow defines the mandatory sequence for implementing a non-trivial feature or bug fix in this repository. Every significant implementation MUST follow it (see `CLAUDE.md` Critical Mandate #3).

## Steps

1. **Open a Goal in the decision graph**
   ```bash
   deciduous goal-start --title "<short title>" --intent "<one-line outcome>"
   ```
   Capture the returned goal ID; all subsequent decisions attach to it.

2. **Record the design decision**
   Before editing code, write a `decision` node describing the chosen approach and the main alternative rejected. Keep it two sentences.
   ```bash
   deciduous decision --goal <ID> --summary "<approach>" --rejected "<alt>"
   ```

3. **Implement**
   - Prefer editing existing files over creating new ones.
   - Reuse helpers in `Sources/` before writing new ones.
   - Record any non-obvious sub-decision as another `deciduous decision`.

4. **Run quality gates**
   Follow [quality_gates.md](./quality_gates.md) end-to-end. Do not proceed on failure — fix and re-run.

5. **Close the goal**
   ```bash
   deciduous goal-complete --goal <ID> --outcome "<what shipped>"
   ```

6. **Commit**
   One commit per logical change. Message should reference the goal ID in the footer: `Goal: <ID>`.

## Exit Criteria
- Decision graph shows a closed Goal with at least one design-decision node.
- All quality-gate checks pass.
- No `in_progress` deciduous nodes remain for this feature.
