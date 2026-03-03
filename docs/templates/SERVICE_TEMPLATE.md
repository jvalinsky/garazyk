# [Service Name] Service

<!-- 
Template for documenting PDS services in the application layer.
Replace all [placeholders] with actual content.
Remove this comment block when creating actual documentation.
-->

## Overview

[Brief description of what this service does and its role in the PDS architecture. 2-3 sentences.]

The `[ServiceClassName]` manages [primary responsibility]. It coordinates between [dependencies] to provide [main functionality].

## Responsibilities

[List the key responsibilities of this service. Use bullet points.]

- [Responsibility 1]
- [Responsibility 2]
- [Responsibility 3]
- [Responsibility 4]

## Architecture

```
[ASCII diagram showing how this service fits into the architecture]
Example:

┌─────────────────────────────────────────┐
│   XRPC [Domain] Endpoints               │
│  (com.atproto.[domain].*)               │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│   [ServiceClassName]                    │
│  - [method1]()                          │
│  - [method2]()                          │
│  - [method3]()                          │
└────────────────┬────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────┐  ┌──────▼────────┐
│ [Dependency1]│  │ [Dependency2] │
│ ([purpose])  │  │ ([purpose])   │
└──────────────┘  └───────────────┘
        │                 │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ [Storage Layer]     │
        └─────────────────────┘
```

## Key Methods

### [Method Name 1]

```objc
- ([ReturnType])[methodName]:(Type1)param1
                   [param2]:(Type2)param2
                      error:(NSError **)error;
```

[Brief description of what this method does.]

**Parameters:**
- `param1`: [Description of parameter 1]
- `param2`: [Description of parameter 2]
- `error`: Error pointer for failure details

**Returns:** [Description of return value]

**Implementation pattern (from [FileName].m lines [X-Y]):**

[Brief explanation of the implementation approach]

```objc
// Code example showing typical implementation pattern
// Extract from actual source file
// Include key logic and error handling
```

**Example usage:**
```objc
// Practical example showing how to call this method
NSError *error = nil;
[ReturnType] result = [service methodName:value1
                                   param2:value2
                                    error:&error];
if (result) {
    // Handle success
} else {
    // Handle error
}
```

### [Method Name 2]

```objc
- ([ReturnType])[methodName]:(Type1)param1
                      error:(NSError **)error;
```

[Brief description of what this method does.]

**Parameters:**
- `param1`: [Description of parameter]
- `error`: Error pointer for failure details

**Returns:** [Description of return value]

**Implementation pattern (from [FileName].m lines [X-Y]):**

[Brief explanation of the implementation approach]

```objc
// Code example showing typical implementation pattern
```

**Example usage:**
```objc
// Practical example showing how to call this method
```

### [Additional Methods]

[Repeat the above pattern for other key methods. Include 3-5 most important methods.]

## Integration Points

### With [Dependency 1]

[Explain how this service integrates with a key dependency]

```objc
@property (nonatomic, strong) [DependencyClass] *[propertyName];
```

[Describe what this dependency provides and how it's used. Include specific examples.]

### With [Dependency 2]

[Explain how this service integrates with another key dependency]

```objc
@property (nonatomic, strong) [DependencyClass] *[propertyName];
```

[Describe what this dependency provides and how it's used.]

### With [Storage/Database Layer]

[Explain how this service persists data]

```objc
@property (nonatomic, strong) [DatabaseClass] *[propertyName];
```

[Describe the data model and storage patterns used.]

## Error Handling

[Document common error scenarios and how to handle them]

| Error | Cause | Handling |
|-------|-------|----------|
| [Error Type 1] | [What causes this error] | [How to handle it] |
| [Error Type 2] | [What causes this error] | [How to handle it] |
| [Error Type 3] | [What causes this error] | [How to handle it] |
| [Error Type 4] | [What causes this error] | [How to handle it] |

## Best Practices

[List best practices for using this service. Use numbered list for important guidelines.]

1. **[Practice Category 1]**
   - [Specific guideline]
   - [Specific guideline]
   - [Specific guideline]

2. **[Practice Category 2]**
   - [Specific guideline]
   - [Specific guideline]

3. **[Practice Category 3]**
   - [Specific guideline]
   - [Specific guideline]

4. **[Practice Category 4]**
   - [Specific guideline]
   - [Specific guideline]

## Common Patterns

### [Pattern Name 1]

[Description of a common usage pattern]

```objc
// Step-by-step code example showing the pattern
// 1. [First step]
[code for step 1]

// 2. [Second step]
[code for step 2]

// 3. [Third step]
[code for step 3]
```

### [Pattern Name 2]

[Description of another common usage pattern]

```objc
// Step-by-step code example showing the pattern
```

### [Pattern Name 3]

[Description of a third common usage pattern]

```objc
// Step-by-step code example showing the pattern
```

## Performance Considerations

[Optional section - include if relevant]

- [Performance tip 1]
- [Performance tip 2]
- [Performance tip 3]

## Thread Safety

[Optional section - include if relevant]

[Describe thread safety guarantees and requirements]

- [Thread safety note 1]
- [Thread safety note 2]

## Testing

[Optional section - include if relevant]

[Describe how to test this service]

```objc
// Example test case
```

## See Also

- [Related Documentation 1](../path/to/doc1)
- [Related Documentation 2](../path/to/doc2)
- [Related Documentation 3](../path/to/doc3)

---

**Version:** [Version number when this was added/updated]  
**Last Updated:** [Date]  
**Source Files:** `ATProtoPDS/Sources/[Path]/[FileName].h`, `ATProtoPDS/Sources/[Path]/[FileName].m`
