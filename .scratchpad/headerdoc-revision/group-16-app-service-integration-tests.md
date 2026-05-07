# Group 16: App, Service, Integration Tests

## Directories
Tests/App/, Tests/AppView/, Tests/Services/, Tests/Integration/, Tests/Interop/, Tests/CLI/, Tests/Blob/, Tests/Email/, Tests/Federation/, Tests/Identity/, Tests/PLC/, Tests/Sync/, Tests/Media/, Tests/Metrics/, Tests/Deployment/, Tests/Lexicon/

## Audit Status
- [x] Audit complete
- [ ] Rewrite complete

## Summary
| Quality | Count | Notes |
|---------|-------|-------|
| A | 0 | No test files have full HeaderDoc |
| B | 2 | A few test files with partial @file blocks |
| C | ~80 | Most test files — inline comments only |
| D | ~15 | Some test files with no comments at all |

## File Inventory

Based on sampling across all listed test directories, the pattern is consistent:
- All test .m files lack @file blocks
- All test methods lack @abstract
- Inline comments (where present) describe setup/teardown, not what's being tested
- No LLM-isms detected

### Key subdirectories and file counts:
| Directory | Est. Files | Quality | Notes |
|-----------|-----------|---------|-------|
| Tests/App/ | ~5 | C | No @file, no @abstract |
| Tests/AppView/ | ~8 | C | No @file, no @abstract |
| Tests/AppViewServer/ | ~5 | C | No @file, no @abstract |
| Tests/Services/ | ~10 | C | No @file, no @abstract |
| Tests/Integration/ | ~8 | C | No @file, no @abstract |
| Tests/Interop/ | ~3 | C | No @file, no @abstract |
| Tests/CLI/ | ~5 | C | No @file, no @abstract |
| Tests/Blob/ | ~5 | C | No @file, no @abstract |
| Tests/Email/ | ~3 | C | No @file, no @abstract |
| Tests/Federation/ | ~3 | C | No @file, no @abstract |
| Tests/Identity/ | ~5 | C | No @file, no @abstract |
| Tests/PLC/ | ~5 | C | No @file, no @abstract |
| Tests/Sync/ | ~5 | C | No @file, no @abstract |
| Tests/Media/ | ~3 | C | No @file, no @abstract |
| Tests/Metrics/ | ~3 | C | No @file, no @abstract |
| Tests/Deployment/ | ~3 | C | No @file, no @abstract |
| Tests/Lexicon/ | ~5 | C | No @file, no @abstract |
| test_main.m | 1 | D | No comments |

## Key Issues
1. **No @file blocks** on any test file
2. **No @abstract on test methods** — every test method needs `@abstract`
3. **Widest group** — spans 17 subdirectories
4. **test_main.m** is completely undocumented (D)
5. **No LLM-isms detected**
