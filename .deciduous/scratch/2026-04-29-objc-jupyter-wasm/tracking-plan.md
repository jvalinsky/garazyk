# objc-jupyter-wasm: Deciduous Tracking Plan

## 1. Node Structure

### Goals (High-Level Objectives)
| Goal Node | Title | Confidence |
|-----------|-------|------------|
| G1 | Run Objective-C REPL as Jupyter kernel in browser via WASM | 85 |
| G2 | Build reproducible WASM toolchain for Objective-C runtime | 90 |
| G3 | Publish demo notebook showing Objective-C interactive evaluation | 80 |

### Decisions (Architecture Choices)
| Decision Node | Title | Rationale |
|---------------|-------|-----------|
| D1 | Use GNUstep libobjc2 for WASM runtime (not Apple objc4) | Portability, Emscripten support |
| D2 | Use Emscripten as WASM compilation target | Mature, supports POSIX, good C/ObjC support |
| D3 | Use postMessage + IFrame transport for Jupyter protocol | Avoids WebSocket requirement in browser-only env |
| D4 | Implement minimal ObjC runtime stub (not full Foundation) | Kernel only needs message sending + basic classes |
| D5 | Use xeus-like kernel template (C++ wrapper) as starting point | Proven pattern for compiling kernels to WASM |

### Actions (Implementation Steps)
| Action Node | Title | Phase |
|-------------|-------|-------|
| A1 | Research existing ObjC WASM ports and Jupyter WASM kernels | Phase 1 |
| A2 | Set up Emscripten build environment for libobjc2 | Phase 2 |
| A3 | Cross-compile minimal ObjC runtime to WASM | Phase 2 |
| A4 | Implement Jupyter kernel protocol handler in C/ObjC | Phase 3 |
| A5 | Build WASM module with bundled runtime + kernel glue | Phase 3 |
| A6 | Implement kernel.js bootstrap and Jupyter handshake | Phase 3 |
| A7 | Create demo notebook with basic ObjC expressions | Phase 4 |
| A8 | Test in JupyterLab and document usage | Phase 4 |

### Outcomes (Completion Status)
| Outcome Node | Title | Status |
|--------------|-------|--------|
| O1 | WASM module loads and initializes ObjC runtime | pending |
| O2 | Basic ObjC expressions evaluate in Jupyter cell | pending |
| O3 | Demo notebook runs in JupyterLab browser | pending |
| O4 | Build pipeline documented and reproducible | pending |

---

## 2. Scratchpad Files

### Location
```
/Users/jack/Software/garazyk/.deciduous/scratch/2026-04-29-objc-jupyter-wasm/
├── master-plan.md              # Master tracking document (node IDs filled in after creation)
├── tracking-plan.md            # This file
├── phase-1-research.md         # Phase 1 scratchpad
├── phase-2-wasm-runtime.md     # Phase 2 scratchpad
├── phase-3-kernel-impl.md      # Phase 3 scratchpad
├── phase-4-testing-demo.md     # Phase 4 scratchpad
├── architecture-decision.md     # Architecture decision record
└── references.md               # Links, papers, repos discovered
```

### Naming Convention
Pattern: `phase-{N}-{short-kebab-desc}.md`
- Date prefix from parent directory: `2026-04-29-objc-jupyter-wasm/`
- Files use kebab-case
- Master plan: `master-plan.md`
- Decision records: `architecture-decision.md`
- Reference collection: `references.md`

### Linking Scratchpads to Deciduous Nodes

After creating nodes, attach scratchpads using:
```bash
deciduous doc attach GOAL_ID /Users/jack/Software/garazyk/.deciduous/scratch/2026-04-29-objc-jupyter-wasm/master-plan.md
deciduous doc attach DECISION_ID /Users/jack/Software/garazyk/.deciduous/scratch/2026-04-29-objc-jupyter-wasm/architecture-decision.md
deciduous doc attach ACTION_ID /Users/jack/Software/garazyk/.deciduous/scratch/2026-04-29-objc-jupyter-wasm/phase-1-research.md
```

Node IDs are filled into each scratchpad's "Node Links" section after creation.

---

## 3. Deciduous Commands to Use

### Creating Nodes

```bash
# Goal nodes (high-level objectives)
deciduous add goal "Run Objective-C REPL as Jupyter kernel in browser via WASM" \
  -d "Enable interactive Objective-C evaluation in browser using WASM-compiled runtime" \
  -c 85 \
  --prompt-stdin << 'EOF'
Create a Jupyter kernel that runs Objective-C code in the browser by compiling the Objective-C runtime to WebAssembly. The kernel should support basic REPL functionality: expression evaluation, result display, and error handling.
EOF

deciduous add goal "Build reproducible WASM toolchain for Objective-C runtime" \
  -d "Emscripten-based build pipeline for GNUstep libobjc2" \
  -c 90

deciduous add goal "Publish demo notebook showing Objective-C interactive evaluation" \
  -d "Shareable demo with basic ObjC expressions running in browser Jupyter" \
  -c 80

# Decision nodes (architecture choices)
deciduous add decision "Use GNUstep libobjc2 for WASM runtime" \
  -d "Over Apple objc4: GNUstep is portable, Emscripten-compatible, and has WASM precedent" \
  -c 90 \
  --prompt-stdin << 'EOF'
Choose the Objective-C runtime to compile to WASM. Options: Apple objc4 (macOS-only, complex deps), GNUstep libobjc2 (portable, Emscripten support), custom minimal runtime (high effort, incomplete).
EOF

deciduous add decision "Use Emscripten as WASM compilation target" \
  -d "Mature toolchain with POSIX support and good C/ObjC compatibility" \
  -c 95

deciduous add decision "Use postMessage + IFrame transport for Jupyter protocol" \
  -d "Avoids WebSocket in browser-only environment; JupyterLab can proxy via kernel.js" \
  -c 85

deciduous add decision "Implement minimal ObjC runtime stub" \
  -d "Kernel only needs message sending + basic classes (NSObject, NSString stubs)" \
  -c 80

deciduous add decision "Use xeus-like kernel template as starting point" \
  -d "Proven C++ wrapper pattern for compiling Jupyter kernels to WASM" \
  -c 75

# Action nodes (implementation steps)
deciduous add action "Research existing ObjC WASM ports and Jupyter WASM kernels" \
  -f "scratch/2026-04-29-objc-jupyter-wasm/phase-1-research.md" \
  -c 90

deciduous add action "Set up Emscripten build environment for libobjc2" \
  -f "scratch/2026-04-29-objc-jupyter-wasm/phase-2-wasm-runtime.md" \
  -c 85

deciduous add action "Cross-compile minimal ObjC runtime to WASM" \
  -c 80

deciduous add action "Implement Jupyter kernel protocol handler in C/ObjC" \
  -c 75

deciduous add action "Build WASM module with bundled runtime + kernel glue" \
  -c 70

deciduous add action "Implement kernel.js bootstrap and Jupyter handshake" \
  -c 70

deciduous add action "Create demo notebook with basic ObjC expressions" \
  -f "scratch/2026-04-29-objc-jupyter-wasm/phase-4-testing-demo.md" \
  -c 85

deciduous add action "Test in JupyterLab and document usage" \
  -c 80

# Outcome nodes (completion status)
deciduous add outcome "WASM module loads and initializes ObjC runtime" \
  -c 0

deciduous add outcome "Basic ObjC expressions evaluate in Jupyter cell" \
  -c 0

deciduous add outcome "Demo notebook runs in JupyterLab browser" \
  -c 0

deciduous add outcome "Build pipeline documented and reproducible" \
  -c 0
```

### Linking Nodes

```bash
# Link goals to enabling decisions
deciduous link GOAL_ID DECISION_ID -r "Architecture decision enables goal" -t enables

# Link decisions to implementation actions
deciduous link DECISION_ID ACTION_ID -r "Decision leads to implementation" -t leads_to

# Link actions to outcomes
deciduous link ACTION_ID OUTCOME_ID -r "Action produces outcome" -t leads_to

# Link goals to each other (dependency)
deciduous link G1 G2 -r "Toolchain required for kernel" -t requires
deciduous link G2 G3 -r "Demo requires toolchain" -t enables
```

### Visualizing Progress

```bash
# Full graph visualization
deciduous graph

# Check status of all nodes
deciduous opencode status

# Show specific node details
deciduous show NODE_ID

# List all nodes by type
deciduous nodes -t goal
deciduous nodes -t decision
deciduous nodes -t action
deciduous nodes -t outcome

# Export for sharing
deciduous sync
```

### Updating Status

```bash
# Mark nodes as in_progress or completed
deciduous status NODE_ID in_progress
deciduous status NODE_ID completed

# Link commit to action when work is done
deciduous add action "..." --commit HEAD
```

---

## 4. Tracking Plan

### Phase 1: Research & Discovery (Week 1)
**Goal:** Understand feasibility and gather references

```bash
# Create goal node for research
deciduous add goal "Validate objc-jupyter-wasm feasibility" -c 90

# Research actions
deciduous add action "Survey existing Objective-C WASM ports" -c 95
deciduous add action "Evaluate GNUstep/libobjc2 WASM compilation path" -c 90
deciduous add action "Study xeus-wasm and pyodide patterns" -c 90
deciduous add action "Prototype minimal objc message send in WASM" -c 70
```

**Scratchpad:** `phase-1-research.md`
- Findings from each research action
- Links to repos, papers, articles
- Feasibility assessment
- Risks identified

### Phase 2: Architecture Decisions (Week 1-2)
**Goal:** Lock in technical approach

```bash
# Architecture decisions
deciduous add decision "WASM Runtime: GNUstep libobjc2" -c 90 --prompt-stdin << 'EOF'
Options considered:
1. Apple objc4 - rejected: macOS-only, complex deps, not Emscripten-compatible
2. GNUstep libobjc2 - chosen: portable, Emscripten precedent, active maintenance
3. Custom minimal runtime - rejected: high effort, likely incomplete
EOF

deciduous add decision "Build Toolchain: Emscripten" -c 95
deciduous add decision "Jupyter Transport: postMessage + IFrame" -c 85
deciduous add decision "Runtime Scope: Minimal stub (no Foundation)" -c 80
```

**Scratchpad:** `architecture-decision.md`
- Decision log with options, rationale, consequences
- Rejected alternatives with reasons
- Architecture diagram (text-based)

### Phase 3: Implementation (Weeks 2-4)
**Goal:** Build working kernel

```bash
# Implementation actions
deciduous add action "Set up Emscripten build env with libobjc2" -c 85 -f "scratch/2026-04-29-objc-jupyter-wasm/phase-2-wasm-runtime.md"
deciduous add action "Compile minimal ObjC runtime to WASM" -c 80
deciduous add action "Implement Jupyter kernel protocol (handshake, execute_request)" -c 75
deciduous add action "Build WASM module with runtime + kernel glue" -c 70
deciduous add action "Implement kernel.js bootstrap" -c 70
deciduous add action "Wire REPL eval loop: Jupyter msg -> objc runtime -> response" -c 65
```

**Scratchpad:** `phase-3-kernel-impl.md`
- Build commands and Makefile snippets
- Code architecture notes
- Bugs encountered and fixes
- Performance notes

### Phase 4: Testing & Demo (Week 4-5)
**Goal:** Validate and showcase

```bash
# Testing actions
deciduous add action "Test basic ObjC expressions in Jupyter cell" -c 85
deciduous add action "Create demo notebook with ObjC features" -c 85 -f "scratch/2026-04-29-objc-jupyter-wasm/phase-4-testing-demo.md"
deciduous add action "Test in JupyterLab + classic notebook" -c 80
deciduous add action "Benchmark WASM startup and eval latency" -c 70
```

**Scratchpad:** `phase-4-testing-demo.md`
- Test matrix (browsers, Jupyter versions)
- Demo notebook content outline
- Bug reports
- Performance results

### Phase 5: Integration & Publication (Week 5-6)
**Goal:** Share with community

```bash
# Integration outcomes
deciduous add outcome "objc-jupyter-wasm builds and runs basic ObjC expressions" -c 0
deciduous add outcome "Demo notebook published and shareable" -c 0
deciduous add outcome "Build pipeline documented in README" -c 0
deciduous add outcome "Works in JupyterLab and classic notebook" -c 0
```

**Final steps:**
```bash
# Mark all goals complete
deciduous status G1 completed
deciduous status G2 completed
deciduous status G3 completed

# Generate writeup
deciduous writeup > /Users/jack/Software/garazyk/.deciduous/scratch/2026-04-29-objc-jupyter-wasm/writeup.md

# Update narratives
# (Edit .deciduous/narratives.md to add objc-jupyter-wasm story)
```

---

## 5. Scratchpad Content

### `master-plan.md`
```markdown
# objc-jupyter-wasm: Objective-C Jupyter Kernel via WASM

Date: 2026-04-29

## Goal
Run an Objective-C REPL as a Jupyter kernel inside the browser using WebAssembly,
enabling interactive Objective-C exploration without a native toolchain.

## Node Links
- Goal nodes: # (fill in after creation)
- Decision nodes: # (fill in after creation)
- Action nodes: # (fill in after creation)
- Outcome nodes: # (fill in after creation)

## Progress Summary
- [ ] Phase 1: Research
- [ ] Phase 2: Architecture
- [ ] Phase 3: Implementation
- [ ] Phase 4: Testing
- [ ] Phase 5: Publication
```

### `phase-1-research.md`
```markdown
# Phase 1 - Research & Discovery

Date: 2026-04-29
Action node: # (fill in)

## Scope
- Survey existing Objective-C WASM ports
- Evaluate GNUstep/libobjc2 compilation path
- Study xeus-wasm, pyodide patterns
- Assess feasibility

## Node Links
- Action node: #
- Related decisions: #

## Findings

### Existing ObjC WASM Work
- [ ] Link to any existing ports
- [ ] GNUstep Emscripten experiments

### Jupyter WASM Kernels (for pattern reference)
- xeus-wasm: C++ kernel framework compiled to WASM
- pyodide: Python in WASM with Jupyter support
- freeknot: WASM kernel template

### Feasibility Assessment
- Runtime compilation: [PENDING]
- Message passing: [PENDING]
- ObjC REPL in browser: [PENDING]

## Risks
1. ObjC runtime size when compiled to WASM
2. Browser memory limits for runtime
3. Jupyter protocol complexity without ZeroMQ

## Decision Needed
- [ ] Choose runtime (libobjc2 vs custom)
- [ ] Choose transport mechanism
```

### `architecture-decision.md`
```markdown
# Architecture Decision Record

Date: 2026-04-29

## Node Links
- Decision nodes: # (fill in after creation)

## Decisions

### D1: Runtime Selection
**Decision:** Use GNUstep libobjc2
**Alternatives considered:**
- Apple objc4: Rejected - macOS-only, complex dependencies
- Custom minimal runtime: Rejected - high effort, incomplete

**Consequences:**
- (+) Portable, Emscripten-compatible
- (+) Proven WASM compilation path
- (-) Larger WASM binary than custom minimal

### D2: Build Toolchain
**Decision:** Emscripten
**Alternatives considered:**
- LLVM wasm backend directly: Complex setup
- wasm-pack (Rust-focused): Not relevant for ObjC

**Consequences:**
- (+) Mature, well-documented
- (+) POSIX compatibility layer
- (-) Learning curve

### D3: Jupyter Transport
**Decision:** postMessage + IFrame
**Alternatives considered:**
- WebSocket: Requires server, not pure browser
- HTTP polling: Too slow for REPL

**Consequences:**
- (+) Works in pure browser environment
- (+) JupyterLab can proxy via kernel.js
- (-) Requires IFrame bridge

### D4: Runtime Scope
**Decision:** Minimal stub (no Foundation)
**Consequences:**
- (+) Smaller WASM binary
- (+) Faster compilation
- (-) Limited ObjC standard library

### D5: Kernel Template
**Decision:** xeus-like C++ wrapper pattern
**Consequences:**
- (+) Proven pattern
- (+) Clear separation of concerns
```

### `phase-2-wasm-runtime.md`
```markdown
# Phase 2 - WASM Runtime Build

Date: 2026-04-29
Action node: #

## Scope
- Set up Emscripten build environment
- Cross-compile GNUstep libobjc2 to WASM
- Create minimal runtime stub

## Node Links
- Action node: #
- Related decisions: # (D1, D2)

## Build Notes

### Emscripten Setup
```bash
# Install Emscripten
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
```

### libobjc2 Compilation
```bash
# Commands to compile libobjc2 to WASM
# (fill in during implementation)
```

### Runtime Stub
Minimal classes needed:
- [ ] NSObject base class
- [ ] objc_msgSend implementation
- [ ] Basic memory management (alloc, retain, release)

## Build Artifacts
- [ ] libobjc2.a (WASM-compatible)
- [ ] runtime.wasm
- [ ] Runtime size: ___ KB

## Issues Encountered
- [ ] List any compilation errors and fixes
```

### `phase-3-kernel-impl.md`
```markdown
# Phase 3 - Kernel Implementation

Date: 2026-04-29
Action node: #

## Scope
- Implement Jupyter kernel protocol
- Build WASM module with runtime + kernel glue
- Implement kernel.js bootstrap

## Node Links
- Action node: #
- Related decisions: # (D3, D5)

## Jupyter Protocol Implementation

### Messages to Handle
- [ ] `kernel_info_request` / `kernel_info_reply`
- [ ] `execute_request` / `execute_reply`
- [ ] `display_data` (for output)
- [ ] `stream` (for stdout/stderr)

### REPL Loop
```
Jupyter message (postMessage)
  -> kernel.js receives
  -> Calls WASM export with code string
  -> WASM: objc runtime evaluates expression
  -> Result returned to JavaScript
  -> Post result back to Jupyter
```

## Code Architecture
```
kernel.js          # Jupyter handshake, postMessage bridge
  └── runtime.wasm # Compiled ObjC runtime + kernel glue
       └── libobjc2.a # Objective-C runtime
```

## WASM Exports Needed
- [ ] `init_runtime()` - Initialize ObjC runtime
- [ ] `eval_code(cStr)` - Evaluate ObjC code string
- [ ] `get_result()` - Get last evaluation result

## Build Commands
```bash
# WASM build command
emcc runtime.c -o runtime.wasm [flags]

# Combine with kernel.js
# (fill in during implementation)
```

## Issues Encountered
- [ ] List bugs and fixes
```

### `phase-4-testing-demo.md`
```markdown
# Phase 4 - Testing & Demo

Date: 2026-04-29
Action node: #

## Scope
- Test basic ObjC expressions
- Create demo notebook
- Test in JupyterLab
- Document usage

## Node Links
- Action node: #
- Related outcomes: #

## Test Matrix

### Browsers
- [ ] Chrome
- [ ] Firefox
- [ ] Safari
- [ ] Edge

### Jupyter Versions
- [ ] JupyterLab 4.x
- [ ] Classic Notebook 6.x

## Demo Notebook Content
```jupyter
# Cell 1: Initialize kernel
// (kernel auto-initializes)

# Cell 2: Basic expression
NSString *greeting = @"Hello from ObjC in WASM!";
NSLog(@"%@", greeting);

# Cell 3: Object creation
NSObject *obj = [[NSObject alloc] init];
NSLog(@"Object: %@", obj);

# Cell 4: Message sending
// (more complex examples)
```

## Performance Results
- WASM startup time: ___ ms
- First eval latency: ___ ms
- Subsequent eval latency: ___ ms
- WASM binary size: ___ KB

## Bugs Found
- [ ] List any bugs and their status

## Documentation
- [ ] README with build instructions
- [ ] Usage guide
- [ ] Demo notebook published to: ____
```

### `references.md`
```markdown
# References

Date: 2026-04-29

## Repositories
- GNUstep libobjc2: https://github.com/gnustep/libobjc2
- xeus-wasm: https://github.com/jupyter-xeus/xeus-wasm
- pyodide: https://github.com/pyodide/pyodide
- freeknot (WASM kernel template): https://github.com/jtpio/freeknot

## Documentation
- Jupyter Kernel Protocol: https://jupyter-client.readthedocs.io/en/latest/messaging.html
- Emscripten docs: https://emscripten.org/docs/
- Objective-C Runtime Programming Guide: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Introduction/Introduction.html

## Papers/Articles
- [ ] Add relevant references as discovered

## Tools
- Emscripten SDK: https://github.com/emscripten-core/emsdk
- wasm-pack: https://github.com/rustwasm/wasm-pack (for reference)
```

---

## Quick Reference: Command Summary

```bash
# Initialize (if starting fresh in new clone)
deciduous init

# Create all nodes for objc-jupyter-wasm
cd /Users/jack/Software/garazyk
# (Run the commands in Section 3 above)

# Check progress
deciduous graph | jq '.nodes[] | select(.metadata_json | contains("objc-jupyter-wasm"))'
deciduous opencode status

# Update node status as work progresses
deciduous status NODE_ID in_progress
deciduous status NODE_ID completed

# Attach scratchpads to nodes
deciduous doc attach GOAL_ID .deciduous/scratch/2026-04-29-objc-jupyter-wasm/master-plan.md
deciduous doc attach ACTION_ID .deciduous/scratch/2026-04-29-objc-jupyter-wasm/phase-1-research.md

# Link nodes to show relationships
deciduous link GOAL_ID DECISION_ID -t enables
deciduous link DECISION_ID ACTION_ID -t leads_to

# Generate final writeup
deciduous writeup > .deciduous/scratch/2026-04-29-objc-jupyter-wasm/writeup.md

# Sync graph
deciduous sync
```
