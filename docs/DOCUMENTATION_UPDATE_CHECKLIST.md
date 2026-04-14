---
title: Documentation Update Checklist
---

# Documentation Update Checklist

This checklist ensures documentation stays synchronized with code changes and maintains accuracy across the PDS Objective-C Implementation Guide.

## When Documentation Updates Are Required

Documentation MUST be updated when:

- [ ] **New XRPC endpoints** are added or modified
- [ ] **Service layer changes** (new services, modified service APIs)
- [ ] **Database schema changes** (new tables, columns, migrations)
- [ ] **Authentication mechanisms** are added or modified
- [ ] **Configuration options** are added, removed, or changed
- [ ] **CLI commands** are added or modified
- [ ] **Platform compatibility** changes (macOS/Linux differences)
- [ ] **Build process** changes (CMake, Xcode, dependencies)
- [ ] **API contracts** change (request/response formats)
- [ ] **Architecture changes** (new components, refactored patterns)

Documentation SHOULD be updated when:

- [ ] **Implementation patterns** change significantly
- [ ] **Error handling** approaches are improved
- [ ] **Performance optimizations** affect usage patterns
- [ ] **Security best practices** are updated
- [ ] **Common issues** are discovered and resolved

## Pre-Commit Checklist

Before committing code changes, verify:

### 1. Code Examples
- [ ] All affected code examples still compile
- [ ] Code examples reflect current API signatures
- [ ] Line references to source files are still accurate
- [ ] Example output matches current behavior

### 2. Architecture Documentation
- [ ] Architecture diagrams reflect current component structure
- [ ] Service interaction patterns are still accurate
- [ ] Request flow diagrams match current routing
- [ ] Database schema diagrams are up-to-date

### 3. Reference Documentation
- [ ] API reference includes new/modified endpoints
- [ ] Configuration reference lists all current options
- [ ] CLI reference documents all commands and flags
- [ ] Error codes and messages are current

### 4. Tutorial Accuracy
- [ ] Tutorials still build and run successfully
- [ ] Tutorial steps match current APIs
- [ ] Expected output matches actual output
- [ ] Dependencies and setup instructions are current

## Documentation Update Process

### Step 1: Identify Affected Documentation

Run this command to find potentially affected docs:

```bash
# Search for references to changed files/components
grep -r "YourChangedComponent" docs/
grep -r "yourChangedFunction" docs/
```

Check these sections based on your changes:

| Change Type | Affected Sections |
|------------|-------------------|
| XRPC endpoint | `04-network-layer/`, `11-reference/api-reference.md` |
| Service layer | `03-application-layer/`, relevant tutorials |
| Database | `05-database-layer/`, `12-diagrams/database-schema.svg` |
| Authentication | `06-authentication/`, `10-tutorials/tutorial-4-auth.md` |
| Repository/Protocol | `07-repository-protocol/` |
| Firehose/Sync | `08-sync-firehose/` |
| Platform compat | `09-platform-compatibility/` |
| Configuration | `11-reference/config-reference.md` |
| CLI | `11-reference/cli-reference.md` |

## Step 2: Update Documentation Files

For each affected file:

1. **Update prose descriptions**
   - [ ] Revise conceptual explanations
   - [ ] Update implementation details
   - [ ] Adjust best practices if needed

2. **Update code examples**
   - [ ] Extract new examples from source
   - [ ] Update line references
   - [ ] Test examples compile and run
   - [ ] Update example output

3. **Update diagrams**
   - [ ] Modify SVG diagrams if architecture changed
   - [ ] Update ASCII art representations
   - [ ] Verify diagram labels are accurate

4. **Update cross-references**
   - [ ] Check internal links still work
   - [ ] Update "See also" sections
   - [ ] Verify glossary terms are current

### Step 3: Verify Documentation Accuracy

Run automated checks:

```bash
# Verify all links work
python3 scripts/test-doc-links.py

# Test code examples compile (if applicable)
./scripts/verify-doc-examples.sh

# Check for broken references
grep -r "TODO\|FIXME\|XXX" docs/
```

Manual verification:

- [ ] Read through updated sections for clarity
- [ ] Verify technical accuracy against code
- [ ] Check for consistency with related sections
- [ ] Ensure terminology matches glossary

## Step 4: Update Related Documentation

Check if these need updates:

- [ ] `docs/SUMMARY.md` (if new pages added)
- [ ] `docs/GLOSSARY.md` (if new terms introduced)
- [ ] `docs/index.md` (if major sections changed)
- [ ] `README.md` (if getting started changed)
- [ ] `AGENTS.md` (if architecture or commands changed)

### Step 5: Test Documentation Build

```bash
# Build documentation site
./scripts/build-docs.sh

# Verify no build errors
# Check generated site in _site/ directory

# Test locally
cd _site && python3 -m http.server 8000
# Visit http://localhost:8000 and verify changes
```

## Code Review Integration

### For Code Authors

When submitting a PR that affects documentation:

1. **In PR description, list documentation changes:**
   ```markdown
   ## Documentation Updates
   - Updated `docs/04-network-layer/method-registry.md` for new registration pattern
   - Added example to `docs/10-tutorials/tutorial-2-accounts.md`
   - Updated `docs/12-diagrams/system-architecture.svg`
   ```text

2. **Include documentation checklist:**
   - [ ] Identified all affected documentation sections
   - [ ] Updated code examples and verified they compile
   - [ ] Updated diagrams if architecture changed
   - [ ] Ran link checker and fixed broken links
   - [ ] Built documentation site and verified changes

### For Code Reviewers

When reviewing PRs, verify:

- [ ] Documentation changes are included for code changes
- [ ] Code examples match the actual implementation
- [ ] Diagrams accurately reflect the changes
- [ ] No broken links or references
- [ ] Terminology is consistent
- [ ] Changes are clear and well-explained

## Consistency Guidelines

### Terminology

Use consistent terms throughout documentation:

| Preferred Term | Avoid |
|---------------|-------|
| XRPC endpoint | RPC method, API endpoint |
| Service layer | Business logic layer |
| Actor database | User database, per-user DB |
| Service database | Shared database, global DB |
| Repository | Repo (except in code) |
| Firehose | Event stream, WebSocket feed |
| DPoP | DPOP, dpop |

### Code Example Format

All code examples should follow this format:

```objc
// Brief description of what this code does
// Source: Garazyk/Sources/Path/To/File.m (lines 123-145)

- (void)exampleMethod {
    // Implementation with comments
}
```

### Diagram Standards

- Use SVG format for all diagrams
- Include text descriptions for accessibility
- Use consistent colors and shapes
- Label all components clearly
- Include diagram source files (if using tools like draw.io)

## Version-Specific Documentation

### For Release Versions

When cutting a release:

1. **Tag documentation with version:**
   ```bash
   git tag -a docs-v1.0.0 -m "Documentation for v1.0.0"
   ```text

2. **Update version references:**
   - [ ] Update version numbers in examples
   - [ ] Update compatibility notes
   - [ ] Update changelog references

3. **Archive old version docs:**
   - [ ] Create versioned documentation branch if needed
   - [ ] Update "Version" selector in docs site

### For Development Documentation

- Mark unstable features clearly: `⚠️ **Experimental**: This feature is under development`
- Use version badges: `Since v1.2.0` or `Deprecated in v2.0.0`
- Link to relevant issues/PRs for context

## Troubleshooting Documentation Issues

### Broken Links

```bash
# Find broken internal links
python3 scripts/test-doc-links.py

# Fix by updating paths or removing dead links
```

## Outdated Code Examples

```bash
# Find examples that reference changed files
grep -r "Sources/OldFileName" docs/

# Update to new file names and verify examples still work
```

## Inconsistent Terminology

```bash
# Find inconsistent terms
grep -r "RPC method" docs/  # Should be "XRPC endpoint"
grep -r "user database" docs/  # Should be "actor database"
```

## Documentation Quality Metrics

Track these metrics to ensure documentation quality:

- **Coverage**: % of components with documentation
- **Freshness**: Days since last update for each section
- **Accuracy**: % of code examples that compile
- **Completeness**: % of checklist items completed per PR
- **Link health**: % of links that work

## Emergency Documentation Updates

For critical fixes that need immediate documentation updates:

1. **Create hotfix branch:**
   ```bash
   git checkout -b docs-hotfix-issue-123
   ```text

2. **Make minimal necessary changes**
   - Focus only on the critical issue
   - Don't refactor or improve unrelated content

3. **Fast-track review:**
   - Request expedited review
   - Merge directly to main if urgent

4. **Follow up:**
   - Create issue for comprehensive review
   - Schedule time for full documentation audit

## Maintenance Schedule

### Weekly
- [ ] Check for new issues labeled "documentation"
- [ ] Review recent PRs for missing doc updates
- [ ] Run link checker

### Monthly
- [ ] Review documentation metrics
- [ ] Update troubleshooting guide with new issues
- [ ] Verify all tutorials still work

### Quarterly
- [ ] Full documentation audit
- [ ] Update all diagrams for accuracy
- [ ] Review and update glossary
- [ ] Check for outdated content

### Per Release
- [ ] Update version-specific content
- [ ] Verify all examples work with new version
- [ ] Update changelog and migration guides
- [ ] Tag documentation with release version

## Resources

- **Documentation source**: `docs/` directory
- **Build script**: `scripts/build-docs.sh`
- **Link checker**: `scripts/test-doc-links.py`
- **Example validator**: `scripts/verify-doc-examples.sh` (if exists)
- **Style guide**: Follow this checklist for consistency
- **Issue tracker**: Label issues with `documentation` tag

## Questions?

If you're unsure whether documentation needs updating:

1. Ask yourself: "Would this change confuse someone reading the docs?"
2. If yes, update the documentation
3. If unsure, ask in PR review or create a documentation issue
4. When in doubt, update it — better to over-document than under-document

---

**Remember**: Documentation is code. Treat it with the same care and rigor as the implementation.
