# Operational Guidance for AI Assistants

This repository contains a suite of Deno packages designed for orchestrating local AT Protocol (Bluesky) networks and running automated End-to-End (E2E) testing scenarios.

## Framework Overview

The project uses a standard Deno monorepo workspace structured in the `packages/` directory, managed via `deno.json`. 

### Key Packages
- **`packages/docker-client`**: Generic Docker interaction primitives.
- **`packages/atproto-client`**: Strongly typed XRPC clients derived from local lexicons.
- **`packages/atproto-topology`**: Zod schemas mapping out PDS/AppView/BGS Docker topologies.
- **`packages/scenario-runner`**: The testing framework and assertion library.

### Execution Scripts
The `scripts/` directory contains CLI wrappers for testing and network management. 
- **`scripts/run_scenarios.ts`**: The main entry point for running the test suite.

## Development Rules

When working in this repository, assistants MUST adhere to the following principles:

1. **Strict TypeScript Compliance**: All code must pass `deno check packages/*/mod.ts`. Ensure strong typing; avoid `any` or `unknown` where possible.
2. **JSR Publishing Constraints**: If modifying public APIs (exports) inside `packages/`, ensure all exports have explicit return types. `atproto-topology` is an exception for exported Zod schemas.
3. **No Direct `../` Imports Across Packages**: Code inside `packages/docker-client` must NOT import directly from `../scenario-runner`. You must use the alias `@garazyk/scenario-runner` defined in `deno.json`.
4. **Code Generation**: The XRPC methods in `@garazyk/atproto-client/lexicons.ts` are generated from the `lexicons/` directory. If lexicons are updated, run `deno run -A packages/atproto-client/scripts/generate.ts` to rebuild the types.

## Available Skills

Skills are located in `.agents/skills/`. The LLM loads them on-demand via the `skill` tool when a task matches their description.

*Note: Many legacy skills related to Objective-C, GNUstep, and SQLite schema architecture have been deprecated in this Deno transition.*