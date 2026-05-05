# Garazyk Refactoring Phase 2: "Slop" Removal & Objective-C Hygiene

## Current Focus:
2.1 Generics and Nullability across `Garazyk/Sources/`
2.2 De-Slop and Ghost Logic Removal
2.3 Robust Parsing Primitives (DIDs, AT-URIs, Dates)

## Plan:
1. Fix nullability (`_Nullable`) and generics (`NSArray<NSString *> *`) across core files identified in the audit.
2. Remove LLM-isms like "robust", "comprehensive" from comments.
3. Fix the `sscanf` date parser in `NSDateFormatter+ATProto.m` and `componentsSeparatedByString:` DID/URI parsers.