---
title: Documentation Style Guide
---

# Documentation Style Guide

This guide defines the writing style, formatting conventions, and best practices for September PDS documentation.

## Table of Contents

- [Writing Style](#writing-style)
- [Voice and Tone](#voice-and-tone)
- [Formatting Conventions](#formatting-conventions)
- [Code Examples](#code-examples)
- [Terminology](#terminology)
- [Structure and Organization](#structure-and-organization)
- [Accessibility](#accessibility)

## Writing Style

### General Principles

1. **Clear and Concise**: Every sentence should add value. Remove unnecessary words.
   - ❌ "In order to create an account, you will need to..."
   - ✅ "To create an account, you need to..."

2. **Active Voice**: Use active voice for clarity and directness.
   - ❌ "The request is processed by the server"
   - ✅ "The server processes the request"

3. **Present Tense**: Write in present tense for immediacy.
   - ❌ "The function will return a value"
   - ✅ "The function returns a value"

4. **Second Person**: Address the reader directly.
   - ❌ "Developers should implement error handling"
   - ✅ "You should implement error handling"

5. **Explain Why, Not Just What**: Help readers understand design decisions.
   - ❌ "Use WAL mode for SQLite"
   - ✅ "Use WAL mode for SQLite to enable concurrent reads during writes"

### Sentence Structure

- **Keep sentences short**: Aim for 15-20 words per sentence
- **One idea per sentence**: Don't pack multiple concepts into one sentence
- **Vary sentence length**: Mix short and medium sentences for readability
- **Use transitions**: Connect ideas with words like "however," "therefore," "additionally"

### Paragraph Structure

- **Start with topic sentence**: State the main idea first
- **Keep paragraphs focused**: One main idea per paragraph
- **Limit paragraph length**: 3-5 sentences is ideal
- **Use white space**: Break up long blocks of text

## Voice and Tone

### Voice Characteristics

**Knowledgeable but not condescending**:
- ✅ "This approach has trade-offs worth considering"
- ❌ "Obviously, you should know this already"

**Helpful and supportive**:
- ✅ "This can be tricky. Here's how to handle it..."
- ❌ "This is simple. Just do X."

**Technical but approachable**:
- ✅ "The MST (Merkle Search Tree) provides authenticated data structures"
- ❌ "The MST is a cryptographically-authenticated lexicographically-ordered..."

**Conversational but professional**:
- ✅ "Let's look at how this works in practice"
- ❌ "Now we're gonna check out how this thing works"

### Tone Guidelines

**For tutorials**: Encouraging and step-by-step
- "Great! You've successfully created your first account."
- "Let's build on what we learned in the previous section."

**For reference documentation**: Precise and factual
- "The `createAccount` method requires three parameters."
- "Returns `nil` if the operation fails."

**For troubleshooting**: Empathetic and solution-focused
- "This error commonly occurs when..."
- "To resolve this issue, try the following steps..."

**For conceptual explanations**: Clear and educational
- "Understanding this concept is key to..."
- "This design decision enables..."

## Formatting Conventions

### Headings

- **Use sentence case**: "Getting started with authentication" not "Getting Started With Authentication"
- **Be descriptive**: Headings should clearly indicate content
- **Use hierarchy properly**: H1 → H2 → H3, don't skip levels
- **Keep concise**: Aim for 5-8 words maximum

**Heading levels**:
- `#` (H1): Page title only (one per page)
- `##` (H2): Major sections
- `###` (H3): Subsections
- `####` (H4): Sub-subsections (use sparingly)

### Lists

**Bulleted lists** for unordered items:
```markdown
- First item
- Second item
- Third item
```

**Numbered lists** for sequential steps:
```markdown
1. First step
2. Second step
3. Third step
```

**List guidelines**:
- Use parallel structure (all items same grammatical form)
- Keep items concise (1-2 lines each)
- Use periods only if items are complete sentences
- Introduce lists with a colon or complete sentence

### Emphasis

- **Bold** for UI elements, important terms, and emphasis: `**important**`
- *Italic* for introducing new terms: `*Merkle Search Tree*`
- `Code` for code elements, file names, commands: `` `fileName.m` ``
- Don't overuse emphasis - it loses impact

### Links

**Internal links** (to other documentation pages):
```markdown
See [Authentication](../06-authentication/oauth2-dpop.md) for details.
```

**External links** (to external resources):
```markdown
Read the [AT Protocol specification](https://atproto.com/specs) for more information.
```

**Link text guidelines**:
- Make link text descriptive: "See the authentication guide" not "Click here"
- Don't use raw URLs in text: Use `[descriptive text](#)` format
- Open external links in new tab (VitePress handles this automatically)

### Tables

Use tables for structured data comparison:

```markdown
| Feature | macOS | Linux |
|---------|-------|-------|
| Security Framework | ✅ | ❌ |
| OpenSSL | ❌ | ✅ |
```

**Table guidelines**:
- Keep tables simple (max 5 columns)
- Use checkmarks (✅) and crosses (❌) for boolean values
- Align columns for readability
- Add caption above table if needed

### Admonitions

Use admonitions for important notes:

```markdown
::: tip
This approach is recommended for production deployments.
:::

::: warning
This operation cannot be undone.
:::

::: danger
Never commit secrets to version control.
:::

::: info
For more details, see the API reference.
:::
```

**When to use**:
- **tip**: Best practices and recommendations
- **warning**: Important caveats or potential issues
- **danger**: Critical security or data loss warnings
- **info**: Additional context or references

## Code Examples

### Code Block Formatting

Always specify the language:

````markdown
# Placeholder
```objc
@interface PDSAccount : NSObject
@property (nonatomic, strong) NSString *did;
@end
```

# Placeholder
````text

## Code Block Features

**Line numbers** (enabled by default):
````markdown
# Placeholder
```objc
// Line numbers appear automatically
```

# Placeholder
````text

**Line highlighting**:
````markdown
# Placeholder
```objc{2,4-6}
// Line 1
// Line 2 - highlighted
// Line 3
// Lines 4-6 highlighted
// Line 5
// Line 6
```

# Placeholder
````text

**File name**:
````markdown
# Placeholder
```objc [PDSAccount.h]
@interface PDSAccount : NSObject
@end
```

# Placeholder
````text

**Code groups** (platform-specific):
````markdown
::: code-group
```objc [macOS]
#import <Security/Security.h>
```

# Placeholder
```objc [Linux]
#import <openssl/evp.h>
```

:::
````text

## Code Example Guidelines

1. **Make examples complete**: Include necessary imports and context
2. **Add explanatory comments**: Explain what code does and why
3. **Use realistic examples**: Show actual usage patterns, not toy examples
4. **Test all code**: Ensure examples compile and run correctly
5. **Follow project style**: Match the project's coding conventions
6. **Keep examples focused**: Show one concept at a time
7. **Provide context**: Explain before and after the code block

**Example structure**:

```markdown
Here's how to create an account:

```objc
// Import required headers
#import "PDSAccountService.h"

// Create account with handle and password
PDSAccount *account = [accountService createAccountWithHandle:@"alice.example.com"
                                                      password:@"secure-password"
                                                         error:&error];
if (account) {
    NSLog(@"Account created: %@", account.did);
}
\```text

**What this code does**:
- Imports the account service header
- Calls `createAccountWithHandle:password:error:` to create a new account
- Checks for success and logs the DID

**Important notes**:
- Always check for errors in production code
- Use strong passwords (this is just an example)
- Store DIDs securely for future reference
```

### Inline Code

Use inline code for:
- Function names: `createAccount`
- Variable names: `accountDID`
- File names: `PDSAccount.m`
- Commands: `npm run build`
- Short code snippets: `@property (nonatomic, strong)`

Don't use inline code for:
- Emphasis (use **bold** instead)
- General terms (use regular text)

## Terminology

### Consistent Terms

Use consistent terminology throughout documentation. Check `GLOSSARY.md` for standard terms.

**Preferred terms**:
- "AT Protocol" not "ATProto" or "AT proto" (except in code)
- "Personal Data Server" or "PDS" not "personal data server"
- "Merkle Search Tree" or "MST" not "merkle search tree"
- "DID" not "did" or "Did" (when referring to the concept)
- "handle" not "username" or "user handle"
- "repository" not "repo" (except in code like `com.atproto.repo.*`)

### Technical Terms

**First use**: Introduce and define technical terms on first use
```markdown
The *Merkle Search Tree* (MST) is a data structure that combines...
```

**Subsequent uses**: Use the term or abbreviation consistently
```markdown
The MST provides authenticated data structures...
```

**Avoid jargon**: Explain technical concepts in accessible language
- ❌ "The MST leverages cryptographic commitments for authenticated data structures"
- ✅ "The MST uses cryptographic hashing to prove data hasn't been tampered with"

### Abbreviations

**First use**: Spell out with abbreviation in parentheses
```markdown
Personal Data Server (PDS)
```

**Subsequent uses**: Use abbreviation
```markdown
The PDS stores user data...
```

**Common abbreviations**:
- PDS: Personal Data Server
- MST: Merkle Search Tree
- DID: Decentralized Identifier
- JWT: JSON Web Token
- DPoP: Demonstration of Proof of Possession
- XRPC: Cross-organizational Remote Procedure Call
- CAR: Content Addressable aRchive
- CBOR: Concise Binary Object Representation

## Structure and Organization

### Page Structure

Every documentation page should follow this structure:

1. **Front matter**: Title, description, outline settings
2. **Page title (H1)**: One per page
3. **Introduction**: What this page covers and why it matters
4. **Main content**: Organized with H2 and H3 headings
5. **Related topics**: Links to related documentation
6. **Summary**: Key takeaways (optional but recommended)

### Content Organization

**Progressive disclosure**: Start simple, add complexity gradually
1. Overview and key concepts
2. Basic usage and examples
3. Advanced topics and edge cases
4. Troubleshooting and best practices

**Logical flow**: Organize content in a logical sequence
- Prerequisites before implementation
- Concepts before code
- Simple examples before complex ones
- Common cases before edge cases

**Chunking**: Break content into digestible sections
- Use headings to create clear sections
- Keep sections focused on one topic
- Use lists to break up dense text
- Add white space between sections

## Accessibility

### Writing for Accessibility

1. **Use clear language**: Avoid unnecessarily complex words
2. **Define acronyms**: Spell out on first use
3. **Provide alt text**: Describe images and diagrams
4. **Use descriptive links**: "See the authentication guide" not "Click here"
5. **Structure with headings**: Use proper heading hierarchy
6. **Avoid directional language**: Don't say "above" or "below" (use links instead)

### Image Alt Text

**Diagrams**:
```markdown
<!-- Image placeholder: System architecture diagram showing PDS components and their interactions -->
```

**Screenshots**:
```markdown
<!-- Image placeholder: Screenshot of the VitePress search interface with "authentication" query -->
```

**Alt text guidelines**:
- Describe what the image shows
- Keep concise (1-2 sentences)
- Don't start with "Image of" or "Picture of"
- Include relevant details for understanding

### Color and Contrast

- Don't rely on color alone to convey information
- Use text labels in addition to color coding
- Ensure sufficient contrast (handled by theme)
- Test in both light and dark modes

## Review Checklist

Before publishing documentation, verify:

- [ ] Front matter is complete (title, description)
- [ ] Headings follow proper hierarchy (H1 → H2 → H3)
- [ ] Code examples are tested and working
- [ ] Links are valid (internal and external)
- [ ] Terminology is consistent with GLOSSARY.md
- [ ] Images have descriptive alt text
- [ ] Writing is clear and concise
- [ ] Voice and tone are appropriate
- [ ] Examples are realistic and complete
- [ ] Cross-references are included
- [ ] Spelling and grammar are correct

## Additional Resources

- **VitePress Markdown**: https://vitepress.dev/guide/markdown
- **Markdown Guide**: https://www.markdownguide.org/
- **Google Developer Documentation Style Guide**: https://developers.google.com/style
- **Microsoft Writing Style Guide**: https://learn.microsoft.com/en-us/style-guide/welcome/

## Questions?

If you're unsure about style or formatting:
1. Check this guide first
2. Look at existing documentation for examples
3. Ask in the documentation channel
4. Create an issue for clarification
