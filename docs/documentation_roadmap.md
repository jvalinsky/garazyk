# Documentation Improvement Roadmap (2026-05-16)

## Current Status

Overall documentation coverage is at **76%**. The project has successfully hit 100% in
`AdminUIServer`, 98% in `Database`, and 96% in `Chat`. Recent efforts have reclassified ~80 files
from "Other" to core subsystems, providing a more accurate baseline. The primary focus now is
addressing the "Services" (50%) and "Core" (63%) subsystems.

## Strategic Objectives

1. **Targeted Coverage Increases:** Raise subsystem-wide coverage for `Services` (50%) and `Core`
   (63%) to >80% by targeting un-documented protocols and enums.
2. **"Other" Bucket Refactoring:** Continue to map the remaining 182 files from "Other" to
   appropriate subsystems.
3. **Hardened Maintenance:** Utilize `doc-coverage.ts` in CI gates to prevent regression.

## Roadmap

### Phase 1: Subsystem Refinement (Next 2 weeks)

- [x] Categorize the "Other" bucket files into logical subsystems.
- [ ] Prioritize documenting Protocols and Enums in `Services` (50%) and `Core` (63%).
- [ ] Add `doc-coverage` gate to CI/CD pipeline for PR validation.

### Phase 2: Structural Hardening

- [ ] Resolve the final `GZLogger.h` Doxygen warning.
- [ ] Update `rewriting-code-comments` skill with advanced patterns for handling Objective-C
      protocols and complex categories.

### Phase 3: Long-term Maintenance

- [ ] Quarterly documentation audit cycle using `scripts/docs/doc-coverage.ts`.
- [ ] Maintain a 85% project-wide coverage floor.

## Task Allocation

- **Automated Audit:** Run `deno task doc:coverage` weekly to track progress.
- **Skill Usage:** Use `rewriting-code-comments` for all future header modifications.
