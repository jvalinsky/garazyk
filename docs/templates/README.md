---
title: Documentation Templates
---

# Documentation Templates

This directory contains templates for creating new documentation following the PDS Objective-C Implementation Guide standards.

## Available Templates

### 1. Service Documentation Template

**File:** `SERVICE_TEMPLATE.md`

**Use for:** Documenting new services in the application layer (e.g., PDSAccountService, PDSRecordService)

**How to use:**
1. Copy `SERVICE_TEMPLATE.md` to `docs/03-application-layer/[service-name].md`
2. Replace all `[placeholders]` with actual content
3. Remove the comment block at the top
4. Fill in all sections with service-specific information
5. Extract code examples from actual source files
6. Update cross-references to related documentation

**Example:**
```bash
cp docs/templates/SERVICE_TEMPLATE.md docs/03-application-layer/notification-service.md
# Edit the file and replace placeholders
```

## 2. XRPC Endpoint Documentation Template

**File:** `XRPC_ENDPOINT_TEMPLATE.md`

**Use for:** Documenting individual XRPC endpoints (e.g., com.atproto.repo.createRecord)

**How to use:**
1. Copy `XRPC_ENDPOINT_TEMPLATE.md` to `docs/11-reference/endpoints/[nsid].md`
2. Replace all `[placeholders]` with actual endpoint details
3. Remove the comment block at the top
4. Document request/response schemas from lexicon definitions
5. Include implementation details from domain method handlers
6. Add practical usage examples

**Example:**
```bash
mkdir -p docs/11-reference/endpoints
cp docs/templates/XRPC_ENDPOINT_TEMPLATE.md docs/11-reference/endpoints/com.atproto.repo.createRecord.md
# Edit the file and replace placeholders
```

## 3. Tutorial Template

**File:** `TUTORIAL_TEMPLATE.md`

**Use for:** Creating new step-by-step tutorials

**How to use:**
1. Copy `TUTORIAL_TEMPLATE.md` to `docs/10-tutorials/tutorial-[N]-[name].md`
2. Replace all `[placeholders]` with tutorial content
3. Remove the comment block at the top
4. Create working example code in `examples/tutorial-[N]-[name]/`
5. Test all code examples to ensure they work
6. Include troubleshooting for common issues

**Example:**
```bash
cp docs/templates/TUTORIAL_TEMPLATE.md docs/10-tutorials/tutorial-7-moderation.md
mkdir -p examples/tutorial-7-moderation/src
# Create tutorial content and working examples
```

## Template Guidelines

### General Principles

1. **Consistency:** Follow the structure and style of existing documentation
2. **Completeness:** Fill in all sections; remove sections only if truly not applicable
3. **Accuracy:** Extract code examples from actual source files, not invented examples
4. **Testing:** Verify all code examples compile and run before committing
5. **Cross-references:** Link to related documentation using relative paths

### Code Examples

- Extract from actual source files with line references
- Include error handling in examples
- Show both success and failure cases
- Keep examples focused and minimal
- Add comments explaining key concepts

### Writing Style

- Use clear, concise language
- Explain "why" not just "what"
- Include practical usage examples
- Document common pitfalls
- Provide troubleshooting guidance

### Version Information

Always include at the bottom of each document:
- Version number when added/updated
- Last updated date
- Source file references
- Related documentation links

## Validation

Before committing new documentation:

1. **Build check:** Ensure documentation builds without errors
   ```bash
   cd docs && bundle exec jekyll build
   ```text

2. **Code validation:** Run code example validation
   ```bash
   ./scripts/validate-doc-code-examples.sh
   ```text

3. **Link validation:** Check all internal links
   ```bash
   ./scripts/validate-doc-links.sh
   ```text

4. **Diagram validation:** Validate SVG diagrams (if applicable)
   ```bash
   ./scripts/validate-doc-diagrams.sh
   ```text

## Documentation Standards

### File Naming

- Use lowercase with hyphens: `service-name.md`
- Match source file names where applicable
- Use descriptive names: `oauth2-dpop.md` not `auth2.md`

### Section Ordering

Follow the template section order:
1. Overview
2. Architecture/Structure
3. Key Methods/Endpoints
4. Integration Points
5. Error Handling
6. Best Practices
7. Common Patterns
8. Examples
9. See Also

### Code Formatting

- Use triple backticks with language identifier: ```objc
- Include file paths in comments: `// From PDSService.m lines 50-100`
- Format consistently with clang-format style
- Keep line length reasonable (< 100 chars)

### Diagrams

- Use ASCII art for simple diagrams
- Use SVG for complex diagrams
- Store SVGs in `docs/12-diagrams/`
- Include alt text for accessibility
- Reference diagrams with relative paths

## Maintenance

### Updating Documentation

When code changes affect documentation:

1. Update the affected documentation files
2. Update version and last-updated date
3. Verify code examples still work
4. Check cross-references are still valid
5. Run validation scripts
6. Update CHANGELOG if significant changes

### Deprecation

When documenting deprecated features:

1. Add deprecation notice at the top
2. Explain what replaces it
3. Provide migration guide
4. Keep documentation for 2 major versions
5. Move to archive after 3 major versions

## Examples

### Good Documentation

✅ Clear, concise overview  
✅ Working code examples from source  
✅ Practical usage patterns  
✅ Error handling shown  
✅ Cross-references to related docs  
✅ Troubleshooting section  
✅ Version information included  

### Poor Documentation

❌ Vague or missing overview  
❌ Invented code examples  
❌ No practical examples  
❌ Missing error handling  
❌ No links to related docs  
❌ No troubleshooting help  
❌ No version information  

## Getting Help

If you need help with documentation:

1. Review existing documentation for examples
2. Check the [Documentation Update Checklist](../DOCUMENTATION_UPDATE_CHECKLIST)
3. Review the [Versioning Strategy](../VERSIONING_STRATEGY)
4. Ask in pull request reviews

## See Also

- [Documentation Update Checklist](../DOCUMENTATION_UPDATE_CHECKLIST)
- [Versioning Strategy](../VERSIONING_STRATEGY)
- [SUMMARY.md](../SUMMARY) — Table of contents
- [GLOSSARY.md](../GLOSSARY) — Terminology reference
