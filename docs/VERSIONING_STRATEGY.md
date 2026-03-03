# Documentation Versioning Strategy

## Overview

This document defines the versioning strategy for the ATProto PDS Objective-C implementation guide. The strategy ensures documentation stays synchronized with code releases while remaining maintainable and accessible.

## Versioning Approach

### Version Numbering

Documentation versions follow the project's semantic versioning (SemVer):
- **Major.Minor.Patch** (e.g., 1.0.0, 1.1.0, 1.1.1)
- Documentation version matches the code release version

### Version Branches

- **main branch** — Latest stable documentation (matches latest release)
- **develop branch** — In-progress documentation (matches develop code)
- **Version tags** — Tagged releases (e.g., v1.0.0, v1.1.0)

## Documentation Update Workflow

### For New Releases

1. **During Development** (on develop branch):
   - Update documentation alongside code changes
   - Mark breaking changes with version notes
   - Update code examples to match new APIs

2. **Before Release** (pre-release checklist):
   - Review all documentation for accuracy
   - Verify all code examples compile and run
   - Update version numbers in _config.yml
   - Test all links and cross-references
   - Update CHANGELOG.md with documentation changes

3. **At Release** (when tagging):
   - Merge develop to main
   - Tag release (e.g., git tag v1.0.0)
   - Deploy documentation to gh-pages
   - Archive previous version if needed

### For Patch Releases

- Update only affected documentation sections
- Maintain backward compatibility in examples
- Add clarifications or corrections
- Fix broken links or typos

### For Major/Minor Releases

- Update architecture diagrams if structure changed
- Add new sections for new features
- Mark deprecated features clearly
- Update all affected code examples
- Review and update tutorials

## Version Indicators

### In Documentation Files

Add version metadata to front matter:

```yaml
---
title: "Service Documentation"
version: "1.0.0"
last_updated: "2024-03-15"
---
```

### Version-Specific Notes

Use callout blocks for version-specific information:

```markdown
> **Version Note (v1.1.0+):** This feature was added in version 1.1.0.

> **Breaking Change (v2.0.0):** The API signature changed in version 2.0.0.

> **Deprecated (v1.2.0):** This method is deprecated. Use `newMethod` instead.
```

### Code Example Versioning

Include version comments in code examples:

```objc
// Available since: v1.0.0
// Updated in: v1.1.0 (added error parameter)
- (void)createRecord:(NSString *)did
          collection:(NSString *)collection
               value:(NSDictionary *)value
               error:(NSError **)error;
```

## Version Archive Strategy

### When to Archive

Archive documentation when:
- Major version releases introduce breaking changes
- Significant architectural changes occur
- Users need to reference older versions

### Archive Location

```
docs/
├── archive/
│   ├── v0.9/          # Pre-1.0 documentation
│   ├── v1.0/          # Version 1.0.x documentation
│   └── v1.1/          # Version 1.1.x documentation
└── [current docs]     # Latest version
```

### Archive Process

1. Copy current docs to `docs/archive/vX.Y/`
2. Add archive notice to archived version
3. Update navigation to link to archived versions
4. Keep archives read-only (no updates)

## Version Selection UI

### In Jekyll Site

Add version selector to _config.yml:

```yaml
versions:
  - version: "1.2.0"
    label: "Latest (1.2.0)"
    path: "/"
  - version: "1.1.0"
    label: "1.1.0"
    path: "/archive/v1.1/"
  - version: "1.0.0"
    label: "1.0.0"
    path: "/archive/v1.0/"
```

### Version Banner

Display version banner on all pages:

```html
<div class="version-banner">
  <span>Documentation Version: 1.2.0</span>
  <a href="/versions">View other versions</a>
</div>
```

## Maintenance Guidelines

### Regular Updates

- **Weekly**: Check for broken links
- **Monthly**: Review code examples for accuracy
- **Per Release**: Full documentation review
- **Quarterly**: Audit archived versions for relevance

### Deprecation Policy

1. **Mark as deprecated** in current version
2. **Keep documentation** for 2 major versions
3. **Move to archive** after 2 major versions
4. **Remove from main docs** after 3 major versions

### Breaking Changes

When documenting breaking changes:
1. Clearly mark the change with version number
2. Explain what changed and why
3. Provide migration guide
4. Show before/after code examples
5. Link to related GitHub issues/PRs

## Version Metadata

### _config.yml Configuration

```yaml
# Documentation version
doc_version: "1.2.0"
code_version: "1.2.0"
last_updated: "2024-03-15"

# Version history
version_history:
  - version: "1.2.0"
    date: "2024-03-15"
    changes: "Added firehose backpressure documentation"
  - version: "1.1.0"
    date: "2024-02-01"
    changes: "Added OAuth 2.0 with DPoP guide"
  - version: "1.0.0"
    date: "2024-01-15"
    changes: "Initial release"
```

### CHANGELOG.md

Maintain a documentation-specific changelog:

```markdown
# Documentation Changelog

## [1.2.0] - 2024-03-15
### Added
- Firehose backpressure handling guide
- WebSocket connection pooling examples

### Changed
- Updated OAuth flow diagrams
- Improved error handling examples

### Fixed
- Corrected JWT token expiration times
- Fixed broken links in tutorial 4

## [1.1.0] - 2024-02-01
...
```

## CI/CD Integration

### Automated Version Checks

CI pipeline should verify:
- Documentation version matches code version
- All version tags are consistent
- No references to unreleased versions
- Archived versions remain unchanged

### Version Tagging Automation

```bash
# On release, automatically:
1. Update _config.yml with new version
2. Tag documentation with release version
3. Deploy to gh-pages
4. Create archive if major version
```

## Best Practices

### DO

- ✅ Update documentation in the same PR as code changes
- ✅ Mark version-specific features clearly
- ✅ Keep archived versions accessible
- ✅ Test all code examples before release
- ✅ Document breaking changes prominently

### DON'T

- ❌ Update archived documentation (read-only)
- ❌ Remove old versions without notice
- ❌ Mix versions in code examples
- ❌ Forget to update version metadata
- ❌ Deploy documentation without testing

## Version Support Policy

### Supported Versions

- **Latest stable**: Full support, active updates
- **Previous minor**: Security fixes, critical corrections
- **Older versions**: Archived, read-only, no updates

### End of Life

When a version reaches end of life:
1. Add EOL notice to archived documentation
2. Recommend upgrading to supported version
3. Keep archived for reference only
4. Remove from version selector after 1 year

## References

- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [Documentation Update Checklist](DOCUMENTATION_UPDATE_CHECKLIST)

## Revision History

- **2024-03-15**: Initial versioning strategy document
