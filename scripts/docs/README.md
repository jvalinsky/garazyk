# Documentation Tooling

This directory contains Node.js-based tooling for managing, validating, and maintaining the Garazyk documentation ecosystem.

## Setup

Install dependencies:

```bash
cd scripts/docs
npm install
```

## Tools

### Migration Tool (`migrate.js`)

Consolidates documentation from multiple source directories into the unified `docs/` structure.

**Features:**
- Preserves git history using `git mv`
- Updates internal cross-references and links
- Generates migration mapping file
- Provides rollback capability
- Configuration-driven migrations

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

Migration configurations are JSON files that define source/destination mappings, file patterns, and options. See `configs/README.md` for detailed documentation.

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

**Features:**
- JSON schema validation
- Semantic rule checking (no nested paths, no duplicates)
- Detailed error reporting
- Configuration summary display

### Validation Tool (`validate.js`)

Validates documentation quality and correctness.

**Features:**
- Markdown linting
- Link validation (internal and anchors)
- Code block language tag verification
- Mermaid diagram syntax validation
- API documentation structure validation

**Usage:**
```bash
npm run validate
```

### Archive Manager (`archive.js`)

Manages outdated documentation archival.

**Features:**
- Moves outdated docs to `docs/archive/` with timestamp
- Generates archive metadata
- Maintains archive index
- Quarterly review scheduling

**Usage:**
```bash
npm run archive
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
- Git (for migration tool)

## Documentation

See the [documentation-consolidation-and-enhancement spec](.kiro/specs/documentation-consolidation-and-enhancement/) for detailed requirements and design.
