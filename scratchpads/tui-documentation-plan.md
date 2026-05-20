# TUI Documentation Plan

## Goal
Encode the API, features, and design decisions of the existing/planned TUI code into cross-linked documentation.

## Phase 1: Exploration and Structure Definition
1. Identify all TUI-related source files (e.g., layout, focus, input, renderer, runtime, and panels).
2. Define the documentation hierarchy:
   - **TUI Architecture**: High-level overview of the event loop, rendering pipeline, and state management.
   - **Core Primitives**: Documentation for ScreenBuffer, diff engine, KeyHandler, and focus ring.
   - **Component Library**: Documentation for layout containers (flexbox/grid) and renderables (Box, Text, TextTable).
   - **Integration / Runtime**: How the TUI hooks into the application runtime (Deno/Node/Zig).

## Phase 2: Documentation Extraction
1. **API Contracts**: Extract TypeScript interfaces and function signatures for the TUI components.
2. **Features**: Document mouse support, keyboard shortcuts, ANSI escape handling, and terminal resizing (SIGWINCH).
3. **Design Decisions**: Document the rationale behind hand-rolled vs. `@opentui/core` usage, layout math, and IPC mechanisms if applicable.

## Phase 3: Cross-linking and Authoring
1. Write the markdown files in `docs/tui/`.
2. Add Mermaid diagrams to illustrate the rendering pipeline and focus management.
3. Ensure cross-links between the architecture overview and specific component APIs.

## Phase 4: Verification
1. Add the new `docs/tui/` files to the overall documentation structure.
2. Run `doc-coverage` and `repo_docs.ts validate` to ensure no broken internal links.
