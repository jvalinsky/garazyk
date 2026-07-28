# Documentation Tooling

Tooling for validating and maintaining the Garazyk documentation. The legacy migration helpers
still run on Node.js; the repo-wide registry, link, and coverage checks run on Deno/TypeScript.

## Setup

Install dependencies:

```bash
cd scripts/docs
npm install
```

## Tools

### Migration Tool (`migrate.js`)

Consolidates documentation from multiple source directories into the unified `docs/` structure.

It preserves git history by using `git mv`, updates internal cross-references and links, writes a
migration mapping file, and supports rollback. Migrations are driven by configuration files.

**Usage:**

```bash
# Run migration with a configuration file
npm run migrate configs/plan-consolidation.json

# Dry run to preview changes
npm run migrate configs/plan-consolidation.json -- --dry-run

# Verbose output
npm run migrate configs/plan-consolidation.json -- --verbose
```

**Configuration:**

Migration configurations are JSON files that define source/destination mappings, file patterns, and
options. See `configs/README.md` for detailed documentation.

Example configuration:

```json
{
  "version": "1.0.0",
  "migrations": [
    {
      "source": "plan",
      "destination": "docs/plans",
      "filePatterns": ["**/*.md"],
      "updateReferences": true
    }
  ]
}
```

### Configuration Validator (`validate-config.js`)

Validates migration configuration files against the schema.

**Usage:**

```bash
npm run validate-config configs/plan-consolidation.json
```

It runs JSON schema validation and semantic rule checks (no nested paths, no duplicates), reports
errors with context, and prints a configuration summary.

### Repo-Wide Registry and Validation (`repo_docs.ts`)

Generates canonical metadata and enforces strict internal link/discoverability checks across
repository markdown.

**Usage:**

```bash
# Generate registry, link graph, orphan report, and index/backlink pages
deno run -A scripts/docs/repo_docs.ts sync

# Blocking validation modes
deno run -A scripts/docs/repo_docs.ts validate --internal-strict --orphans

# Non-blocking scheduled external link report
deno run -A scripts/docs/repo_docs.ts validate --external-report
```

### Deno/TypeScript API Documentation

The scenario harness API is documented across `scripts/lib/deno/` (individual modules: `config.ts`, `runner.ts`, `client.ts`, `assertions.ts`).

```bash
# Install or refresh the docs package dependencies after package metadata changes
npm --prefix scripts/docs install

# Lint exported TSDoc/JSDoc and public type references
deno task doc-lint

# Regenerate committed TypeDoc HTML under scripts/docs/api/
npm --prefix scripts/docs run api:ts

# Report TypeScript documentation coverage for harness and dashboard exports
deno task doc:ts-coverage

# Enforce the current conservative CI baseline for the public harness
deno task doc:ts-coverage:ci

# Generate local Deno HTML docs under scripts/docs/
deno task doc:serve
```

Objective-C HeaderDoc coverage remains separate:

```bash
deno task doc:coverage --by-subsystem
```

## Development

### Linting

```bash
npm run lint        # Check for issues
npm run lint:fix    # Auto-fix issues
```

### Testing

```bash
npm test
```

## Requirements

- Node.js >= 18.0.0
- Deno >= 2.0.0
- Git (for migration tool)

## Documentation

See the [Documentation Map](../../docs/11-reference/documentation-map.md) for current repository
documentation conventions and ownership.
