---
title: [Page Title]
description: [Brief description for SEO and search - 1-2 sentences]
outline: deep
---

# [Page Title]

[Opening paragraph that introduces the topic and explains what this page covers. Answer: What is this? Why does it matter? Who should read this?]

## Overview

[Provide a high-level overview of the topic. Set context before diving into details.]

### Key Concepts

[List and briefly explain the main concepts covered on this page:]

- **Concept 1**: Brief explanation
- **Concept 2**: Brief explanation
- **Concept 3**: Brief explanation

## Why This Matters

[Explain the importance and real-world relevance of this topic. Answer: Why should developers care about this? What problems does it solve?]

In production systems, [explain production relevance and impact].

## [Main Section 1]

[Detailed explanation of the first major topic. Use clear, conversational technical writing.]

### [Subsection 1.1]

[Break down complex topics into digestible subsections.]

```objc
// Code example with clear comments
@interface ExampleClass : NSObject

// Explain what this property does
@property (nonatomic, strong) NSString *exampleProperty;

// Explain what this method does
- (void)exampleMethod;

@end
```

**What this code does:**
- [Explain line by line or concept by concept]
- [Focus on the "why" not just the "what"]
- [Mention any gotchas or important details]

**Design decisions:**
- [Explain why this approach was chosen]
- [Discuss trade-offs and alternatives]
- [Mention when to use different approaches]

### [Subsection 1.2]

[Continue with related concepts, building progressively from simple to complex.]

## [Main Section 2]

[Second major topic with similar structure.]

### Real-World Example

[Provide a practical, real-world example that shows how this is used in production.]

```objc
// Realistic code example
// Show actual usage patterns
```

**In practice:**
- [Explain how this works in real applications]
- [Mention common use cases]
- [Discuss performance implications]

## Common Patterns

[Document common implementation patterns and best practices.]

### Pattern 1: [Pattern Name]

**When to use**: [Describe the scenario where this pattern applies]

**Implementation**:

```objc
// Code example showing the pattern
```

**Advantages**:
- [List benefits of this approach]

**Disadvantages**:
- [List limitations or trade-offs]

### Pattern 2: [Pattern Name]

[Repeat structure for additional patterns]

## Common Pitfalls

[Document common mistakes and how to avoid them.]

### Pitfall 1: [Mistake Description]

**Problem**: [Describe what goes wrong]

**Why it happens**: [Explain the root cause]

**Solution**: [Show how to fix or avoid it]

```objc
// Bad approach (don't do this)
// ...

// Good approach (do this instead)
// ...
```

### Pitfall 2: [Mistake Description]

[Repeat structure for additional pitfalls]

## Troubleshooting

[Provide solutions for common issues developers encounter.]

### Issue: [Problem Description]

**Symptoms**: [How you know you have this problem]

**Causes**:
- [Possible cause 1]
- [Possible cause 2]

**Solutions**:
1. [Step-by-step solution]
2. [Alternative approach if first doesn't work]

**Prevention**: [How to avoid this issue in the future]

### Issue: [Problem Description]

[Repeat structure for additional issues]

## Best Practices

[List recommended practices for this topic.]

1. **[Practice 1]**: [Explanation and rationale]
2. **[Practice 2]**: [Explanation and rationale]
3. **[Practice 3]**: [Explanation and rationale]

## Performance Considerations

[Discuss performance implications and optimization strategies.]

- **[Consideration 1]**: [Impact and recommendations]
- **[Consideration 2]**: [Impact and recommendations]
- **[Consideration 3]**: [Impact and recommendations]

## Security Considerations

[If applicable, discuss security implications and best practices.]

- **[Security aspect 1]**: [Risks and mitigations]
- **[Security aspect 2]**: [Risks and mitigations]

## Platform-Specific Notes

[If applicable, document differences between macOS and Linux/GNUstep.]

### macOS

[macOS-specific implementation details or considerations]

### Linux/GNUstep

[Linux-specific implementation details or considerations]

## Related Topics

[Link to related documentation that readers might find helpful.]

- [Related Topic 1](#) - Brief description
- [Related Topic 2](#) - Brief description
- [Related Topic 3](#) - Brief description

## Further Reading

[Link to external resources, specifications, or additional documentation.]

- [External Resource 1](https://example.com) - Description
- [External Resource 2](https://example.com) - Description
- [AT Protocol Specification](https://atproto.com/specs) - Official specs

## Summary

[Provide a brief summary of key takeaways from this page.]

**Key points to remember**:
- [Main takeaway 1]
- [Main takeaway 2]
- [Main takeaway 3]

**Next steps**:
- [Suggested next action or page to read]
- [Related tutorial or guide]

---

## Template Usage Notes

**When using this template:**

1. **Replace all [bracketed] placeholders** with actual content
2. **Remove sections that don't apply** to your topic
3. **Add sections as needed** for your specific topic
4. **Maintain consistent voice**: Clear, conversational, technical but approachable
5. **Focus on "why" not just "what"**: Explain design decisions and trade-offs
6. **Include real examples**: Show actual usage patterns, not just toy examples
7. **Cross-reference liberally**: Link to related documentation
8. **Use consistent terminology**: Check GLOSSARY.md for standard terms
9. **Test all code examples**: Ensure they compile and run correctly
10. **Consider your audience**: Write for developers learning the system

**Front matter guidelines:**
- `title`: Should match the H1 heading
- `description`: 1-2 sentences for SEO, appears in search results
- `outline: deep`: Shows all headings in table of contents (use `[2,3]` to limit depth)

**Code block guidelines:**
- Always specify language: ` ```objc `
- Include comments explaining what code does
- Show complete, runnable examples when possible
- Use line highlighting for emphasis: ` ```objc{2,4-6} `
- Add file names when helpful: ` ```objc [FileName.m] `

**Writing style:**
- Use active voice: "The system processes requests" not "Requests are processed"
- Be concise but thorough: Every sentence should add value
- Use examples: Show, don't just tell
- Anticipate questions: Answer "why" and "how" proactively
- Build progressively: Simple concepts first, then complexity
