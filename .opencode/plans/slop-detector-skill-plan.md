# Plan: Create "Slop Detector" Skill

## Goal
Implement a new skill called `slop-detector` to identify LLM-generated "vibe-code" and bad engineering patterns.

## TDD Status

### 1. RED Phase (Baseline) - COMPLETED
- Tasked a subagent with creating `PDSSyncService`.
- Observed "vibe-coding" patterns:
    - **Placeholderism**: `@"bafkreiplaceholder"`
    - **Ghost Logic**: Comments restating method names.
    - **Boilerplate Bloat**: Redundant properties and "robust" logging stubs.
    - **Rationalization**: Claims of "professional" and "robust" implementation despite stubs.

### 2. GREEN Phase (Drafting) - IN PROGRESS
- Drafted the `SKILL.md` content (see below).
- Identified core categories: Ghost Logic, Placeholderism, Boilerplate, Fragile Parsing, LLM-isms.
- **NEW RESEARCH ADDED:** 
    - **Insecure Defaults**: Hardcoded debug flags (`debug=True`), missing path traversal guards.
    - **Design Smells**: Unnecessary complexity in simple tasks, over-parameterization.
    - **Linguistic Markers**: "Seamlessly", "Robustly", "Orchestrate".
    - **Hallucinated Logic**: Methods that look like they work but use non-existent library flags or logic.

### 2.1 LLM-ism Code Comments (Chatty & Generic)
- **Indicators:**
    - **The "What" Header**: Comments that restate the method name in sentence form (e.g., `// This method handles repository sync`).
    - **AI-Tutor Tone**: Explaining basic language features or library functions as if they were complex (e.g., `// We use a dictionary for fast lookup`).
    - **Passive/Third-Person**: Overuse of "This method ensures...", "It's important to note...", "Note that...".
    - **Generic Justification**: "We use [X] because it provides a robust solution for [Y]" without project-specific context.
    - **Redundant Sequence Comments**: `// Step 1: Initialize`, `// Step 2: Process`, `// Step 3: Return`.

### 3. REFACTOR Phase (Bulletproofing) - PENDING
- Add explicit counters for "stubs for future work" rationalization.
- Refine detection regex patterns.

---

## Skill Content (Draft)

**Name:** slop-detector
**Description:** Use when reviewing code or searching the codebase for patterns that suggest low-effort LLM generation ("vibe-coding"), architectural shortcuts, or redundant boilerplate.

### Symptoms of Slop
- **Ghost Logic**: Redundant comments explaining the "what" instead of "why".
- **Placeholderism**: Hardcoded strings like `@"placeholder"` in "final" code.
- **Boilerplate Bloat**: Massive repetitive blocks (descriptors, handlers).
- **Fragile Parsing**: `[uri componentsSeparatedByString:@"/"][2]` instead of proper parsing.
- **LLM-isms**: Overuse of "robust", "ensure", "leverage", "comprehensive".

### Red Flags
- Double imports.
- `return nil` stubs integrated into main flows.
- Magic numbers in string parsing.
- Catch-all "Manager" or "Service" classes.

---

## Next Steps (Post-Plan Mode)
1. Write the final skill to `.opencode/skills/slop-detector/SKILL.md`.
2. Run a "GREEN" test by tasking a subagent to *refactor* the `PDSSyncService` using the new skill.
3. Verify the agent removes placeholders and redundant comments.
4. Finalize and push to remote.
