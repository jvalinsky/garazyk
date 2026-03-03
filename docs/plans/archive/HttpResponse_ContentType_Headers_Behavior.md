# HttpResponse Content-Type and Headers Behavior

**Document:** HttpResponse Content-Type Property vs Headers  
**Created:** 2026-01-15T18:41:43Z  
**Git Commit:** 36afc86 (36afcbc42446bcec7884d62a6142b7bcf1156688)  
**Author:** ATProtoPDS Development Team  
**Issue Reference:** Test failure in MSTViewerHandlerTests.testHandleRequestIndex

## Summary

Setting the `contentType` property on `HttpResponse` does NOT automatically update the `headers` dictionary. This is a common pitfall that can cause test failures and incorrect HTTP responses.

## The Problem

```objc
HttpResponse *response = [[HttpResponse alloc] init];
response.contentType = @"text/html; charset=utf-8";
// headers[@"Content-Type"] is still nil at this point!
```

The `contentType` property is a convenience property that stores the content type string, but it does not propagate to the `headers` dictionary until serialization occurs in `[HttpResponse serialize]`.

## Impact

1. **Unit tests fail** when checking `response.headers[@"Content-Type"]` immediately after setting `contentType`
2. **Debugging confusion** - the value appears set but isn't reflected in headers
3. **Inconsistent behavior** - serialization works correctly, but direct header access doesn't

## Correct Patterns

### Pattern 1: Explicit Header Setting (Recommended for handlers)

```objc
- (void)serveIndex:(HttpResponse *)response {
    NSString *html = [self loadAsset:@"index.html"];
    if (html) {
        response.statusCode = HttpStatusOK;
        [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
        response.contentType = @"text/html; charset=utf-8";
        [response setHeader:response.contentType forKey:@"Content-Type"];  // Explicit!
    }
}
```

### Pattern 2: Rely on Serialization (For internal code)

```objc
HttpResponse *response = [[HttpResponse alloc] init];
response.contentType = @"text/html; charset=utf-8";
[response setBody:data];
// Don't check headers directly - check serialized output or use setHeader
```

### Pattern 3: Use setJsonBody (Automatic content-type)

```objc
HttpResponse *response = [[HttpResponse alloc] init];
[response setJsonBody:json];  // Automatically sets contentType AND headers
```

## HttpResponse.m Implementation Details

From `ATProtoPDS/Sources/Network/HttpResponse.m`:

```objc
- (instancetype)init {
    // ...
    _contentType = @"application/json; charset=utf-8";  // Default
    // headers is populated during serialize, not in init
}

- (void)setJsonBody:(NSDictionary *)json {
    _jsonBody = [json copy];
    // ...
    self.contentType = @"application/json; charset=utf-8";
    // Note: headers NOT updated here either
}
```

The `Content-Type` header is only added to `headers` during `[serialize]`:

```objc
- (NSData *)serialize {
    // ...
    if (self.contentType) {
        [self setHeader:self.contentType forKey:@"Content-Type"];  // Here!
    }
    // ...
}
```

## Affected Methods

The following methods do NOT update `headers[@"Content-Type"]`:

1. `response.contentType = @"text/html"` - Property setter
2. `[response setJsonBody:json]` - JSON body setter

Only `[response setHeader:forKey:]` and `[response serialize]` update the headers dictionary.

## Test Coverage

A new test file was added at `ATProtoPDS/Tests/Network/HttpResponseTests.m` with the following test cases:

- `testContentTypePropertyDoesNotUpdateHeaders` - Documents current behavior
- `testSetHeaderUpdatesHeadersCorrectly` - Shows correct usage
- `testSerializeAddsContentTypeToHeaders` - Confirms serialization works
- `testMSTViewerHandlerPatternWorks` - Tests the fix pattern
- `testDefaultContentTypeIsApplicationJson` - Baseline test
- `testJsonBodySetsContentType` - Documents that setJsonBody also doesn't update headers

## Related Files

| File | Line | Description |
|------|------|-------------|
| `Sources/Network/HttpResponse.h` | 60 | `contentType` property declaration |
| `Sources/Network/HttpResponse.m` | 39-50 | `init` implementation |
| `Sources/Network/HttpResponse.m` | 98-120 | `serialize` implementation |
| `Sources/App/MSTViewer/MSTViewerHandler.m` | 71-82 | Fixed handler using correct pattern |

## Lessons Learned

1. Always use `[response setHeader:forKey:]` when you need immediate header access
2. Don't rely on property setters to update backing dictionaries
3. Add tests for behavioral assumptions that aren't documented
4. Check `headers` dictionary directly in tests, not serialized output

## References

- Issue: Test failure in `MSTViewerHandlerTests.testHandleRequestIndex` - Content-Type header not found in `res.headers[@"Content-Type"]`
- Fix commit: 36afcbc - "fix: return empty MST on load failure to prevent hangs"
- Previous memory debugging session documented in `docs/guides/objective_c_tips.md`

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
