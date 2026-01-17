name: slop-detector
description: Use when reviewing code or searching the codebase for patterns that suggest low-effort LLM generation ("vibe-coding"), architectural shortcuts, or redundant boilerplate.

# Slop Detector

## Overview
Detects "slop"—code that appears professional but lacks engineering depth, is repetitively generated, or uses fragile shortcuts. Slop often hides behind authoritative comments and "robust" boilerplate.

## Symptoms of Slop

### 1. Ghost Logic & Redundant Comments
Comments that restate the code exactly or explain *what* is happening instead of *why*.
- `// This method handles repository sync` before `-(void)handleSync...`
- `// Step 1: Initialize`, `// Step 2: Process` sequence comments.
- AI-Tutor tone: `// We use a dictionary for fast lookup`.

### 2. Placeholderism
Hardcoded "placeholder" strings or values that are integrated into "final" logic.
- `@"bafkreiplaceholder"`
- `return @{@"status": @"ok"}; // TODO: implement`

### 3. Boilerplate Bloat (Copy-Paste)
Excessive repetition of nearly identical methods or descriptors instead of abstraction.
- 50+ manual property-to-dictionary mappings.
- Identical error handling blocks copied across 20+ handlers.

### 4. Fragile String Parsing
Using simple string splitting for structured data (like URLs or DIDs) instead of dedicated parsers.
- `[uri componentsSeparatedByString:@"/"][2]` to extract a DID.

### 5. LLM-isms (Linguistic Markers)
Specific words and phrases often used by LLMs to sound "professional":
- **Words**: "Robust", "Comprehensive", "Leverage", "Orchestrate", "Seamlessly".
- **Phrases**: "This method ensures...", "It's important to note...", "Note that...".

### 6. Insecure Defaults
- Hardcoded debug flags (`debug=YES`) in source.
- Missing path traversal guards in file-serving logic.

## Quick Reference: Red Flags

| Red Flag | Description |
|----------|-------------|
| **Double Imports** | Importing the same header twice or redundant system headers. |
| **Nil-Returns** | Methods integrated into core flow that just `return nil` with a "TODO". |
| **Magic Numbers** | Array indices (like `[2]`) in string parsing logic. |
| **The "Manager" Trap** | Large classes named `Manager` or `Service` with no single responsibility. |

## Rationalization Table

| Excuse | Reality |
|--------|---------|
| "It's just a stub for future work" | Stubs in main branches are technical debt. Use protocols or clear failure states. |
| "This makes the code more robust" | Adding "robust" to a comment doesn't improve the code. It masks simplicity. |
| "Following existing patterns" | If the existing pattern is slop, you're just propagating technical debt. |

## Implementation: Detection Patterns

Use `grep` to find common LLM-isms:
```bash
grep -rE "robust|ensure|leverage|comprehensive|This method" Sources/
```

Check for fragile parsing:
```bash
grep -r "componentsSeparatedByString:" Sources/
```

Check for placeholder stubs:
```bash
grep -r "placeholder" Sources/
```

## Common Mistakes
- **Pruning too much**: Don't delete necessary comments; only delete redundant ones.
- **Ignoring context**: some "Service" classes are actually well-defined; check the method count and line count.
