# Group 06: App & AppView

## Directories
App/, AppView/

## Audit Status
- [x] Audit complete
- [ ] Rewrite complete

## Summary
| Quality | Count | Notes |
|---------|-------|-------|
| A | 8 | App/PDSApplication.h, App/PDSConfiguration.h, AppView/AppViewIdentityHelper.h, and 5+ others with full HeaderDoc |
| B | 20 | Most AppView/Server/ and AppView/Services/ files — partial HeaderDoc |
| C | 10 | App/ .m files, AppView/ .m files — @file blocks missing |
| D | 0 | |

## File Inventory

### App/ (10 .h files)
| File | Quality | Issues |
|------|---------|--------|
| AppDelegate.h | B | Has @file but methods lack @param/@return |
| MSTViewerHandler.h | B | Has @file/@abstract but missing @param on methods |
| NodeInfoHandler.h | B | Partial docs |
| NodeInfoProvider.h | B | Partial docs |
| NodeInfoSchemas.h | B | Partial docs |
| OAuthDemoHandler.h | B | Partial docs |
| PDSApplication.h | A | Full HeaderDoc: @file, @class, @method with @abstract/@param/@return |
| PDSConfiguration.h | A | Full HeaderDoc with @file, @enum, @property docs |
| PDSController.h | B | Has @file but methods need @param/@return |
| PDSReadinessCheck.h | B | Partial docs |

### AppView/ (28 .h files)
| File | Quality | Issues |
|------|---------|--------|
| AppViewIdentityHelper.h | A | Full HeaderDoc |
| Server/Admin/AppViewAdminRoutePack.h | B | Partial docs |
| Server/AppViewDatabase.h | B | Partial docs |
| Server/AppViewRuntime.h | B | Partial docs |
| Server/AppViewTypes.h | B | Partial docs |
| Server/Backfill/AppViewBackfillOrchestrator.h | B | Partial docs |
| Server/Backfill/AppViewBackfillWorker.h | B | Partial docs |
| Server/Config/AppViewConfiguration.h | B | Partial docs |
| Server/Indexers/*.h | B | All have @file but missing @param/@return on methods |
| Server/Ingest/AppViewIngestEngine.h | B | Partial docs |
| Server/Relevance/AppViewRelevanceSet.h | B | Partial docs |
| Services/*.h | B | All have @file/@class but methods need @param/@return |

### .m files (all groups)
| Pattern | Quality | Issues |
|---------|---------|--------|
| All .m files | C | Missing @file blocks and @method docs |

## Key Issues
1. **.m files universally lack @file blocks and method docs**
2. **AppView/Services/ .h files**: Have @file and @class but methods missing @param/@return
3. **AppView/Server/Indexers/**: Consistent partial docs but incomplete
4. **No LLM-isms or marketing language detected**
5. **No nullability documentation gaps** — NS_ASSUME_NONNULL used consistently
