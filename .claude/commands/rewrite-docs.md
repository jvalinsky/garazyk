---
description: Rewrite code comments and docs to remove LLM-isms and marketing language
allowed-tools: Read,Edit,Glob,Grep
argument-hint: <file-pattern>
---

# Documentation Rewriter

Rewrite code comments and documentation to remove LLM-isms, marketing language, and excessive enthusiasm. Replace with clear, concise, technical writing.

## What This Fixes

### LLM-isms to Remove
Based on research, LLMs exhibit distinct patterns:
- **Overused transitions**: "Let's", "Note that", "It's important to note", "Keep in mind"
- **Elaborate constructions**: "serves as" instead of "is", "ventured into" instead of "was"
- **Noun-heavy style**: Excessive nominalizations (2x human rate)
- **Hedging phrases**: "may", "might", "could potentially"
- **Metaphors**: "tapestries", "landscape", "ecosystem", "journey"
- **Marketing phrases**: "unlock potential", "seamless", "robust", "powerful"
- **False enthusiasm**: Multiple exclamation points, excessive emojis

Sources:
- [Writing in the Age of LLMs](https://www.sh-reya.com/blog/ai-writing/)
- [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
- [Contrasting Linguistic Patterns in Human and LLM-Generated News Text](https://link.springer.com/article/10.1007/s10462-024-10903-2)

### Marketing Language to Remove
- **Buzzwords**: "cutting-edge", "revolutionary", "game-changing", "innovative"
- **Vague claims**: "high-performance", "enterprise-grade", "world-class"
- **Feature bloat**: "seamlessly integrates", "powerful capabilities"
- **Emotional appeals**: "amazing", "incredible", "fantastic"
- **Empty modifiers**: "simply", "just", "easily", "quickly"

Sources:
- [10 Technical Writing Best Practices](https://www.documind.chat/blog/technical-writing-best-practices)
- [Tips for Using Plain Language in Technical Communication](https://techcomm.unt.edu/news/tips-using-plain-language-technical-communication.html)

### Code Comment Anti-Patterns
- **Redundancy**: Comments that repeat what code says
- **Outdated comments**: Documentation that contradicts code
- **What instead of why**: Describing what code does instead of why
- **Excessive detail**: Long explanations for simple code
- **Jargon**: Unnecessary technical terms

Sources:
- [Stack Overflow: Best practices for writing code comments](https://stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/)
- [MIT Broad Institute: Coding and Comment Style](https://mitcommlab.mit.edu/broad/commkit/coding-and-comment-style/)
- [The Engineer's Guide to Writing Meaningful Code Comments](https://www.stepsize.com/blog/the-engineers-guide-to-writing-code-comments)

## Rewriting Principles

### 1. Use Active Voice
**Before**: "The data is processed by the handler"
**After**: "The handler processes the data"

### 2. Be Direct
**Before**: "Let's create a function that will help us validate the input"
**After**: "Validates input data"

### 3. Remove Hedging
**Before**: "This might potentially cause issues in some cases"
**After**: "Throws error if input is null"

### 4. Explain Why, Not What
**Before**: "Loop through array and add to sum"
**After**: "Accumulate total for budget calculation"

### 5. Use Technical Terms Correctly
**Before**: "This powerful algorithm seamlessly handles edge cases"
**After**: "Handles null, empty, and boundary values"

### 6. Remove Marketing Fluff
**Before**: "Our innovative solution provides a robust framework"
**After**: "Framework for X, Y, Z"

### 7. Be Concise
**Before**: "It is important to note that this function, when called, will perform validation"
**After**: "Validates input before processing"

## Usage

### Scan Files for Issues
```bash
/rewrite-docs *.md
/rewrite-docs ATProtoPDS/Sources/**/*.{h,m}
/rewrite-docs docs/
```

### Process Arguments

Based on $ARGUMENTS:

1. **Parse input**: Extract file patterns or paths
2. **Scan files**: Use Glob to find matching files
3. **Read content**: Use Read to examine each file
4. **Identify issues**: Flag LLM-isms, marketing language, anti-patterns
5. **Generate rewrites**: Apply principles to create cleaner versions
6. **Show changes**: Present before/after for user review
7. **Apply edits**: Use Edit to update files with user approval

## Analysis Checklist

For each file, check:

### Documentation Files (*.md, README, etc.)
- [ ] Remove emojis unless essential
- [ ] Replace "powerful", "robust", "seamless"
- [ ] Remove "Let's", "Note that", "It's important"
- [ ] Change passive to active voice
- [ ] Remove hedging ("may", "might", "could")
- [ ] Replace metaphors with direct statements
- [ ] Remove exclamation points
- [ ] Simplify complex constructions

### Code Comments
- [ ] Remove comments that duplicate code
- [ ] Change "what" comments to "why" comments
- [ ] Remove outdated comments
- [ ] Simplify verbose explanations
- [ ] Remove unnecessary jargon
- [ ] Fix inconsistent style
- [ ] Update to match current code

### Headers and Summaries
- [ ] Remove marketing slogans
- [ ] State purpose directly
- [ ] Remove buzzwords
- [ ] Be specific about functionality
- [ ] Remove empty claims

## Example Transformations

### Documentation
```markdown
# Before
✅ **High-Performance** - Optimized for speed with powerful caching! 🚀

# After
Caches responses for 5-10 minutes to reduce API calls
```

### Code Comment
```objc
// Before
// Let's create a helper that will seamlessly validate the handle

// After
// Validates handle format per AT Protocol spec (RFC 1123)
```

### README
```markdown
# Before
This innovative solution provides a robust framework that seamlessly integrates with your existing infrastructure, offering powerful capabilities for enterprise-grade applications.

# After
Framework for X that integrates with Y via Z protocol.
```

## Output Format

For each file analyzed, provide:

1. **File path**
2. **Issue count** by category
3. **Suggested changes** with line numbers
4. **Before/after** snippets
5. **Confidence rating** (how certain the change is correct)

Ask for confirmation before applying changes.

## Best Practices

Based on research:

1. **Comments should clarify intent, not duplicate code** - [Stack Overflow](https://stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/)
2. **Use plain language** - [Microsoft Manual of Style](https://www.documind.chat/blog/technical-writing-best-practices)
3. **Be concise** - [MIT Broad](https://mitcommlab.mit.edu/broad/commkit/coding-and-comment-style/)
4. **Update docs with code** - [TechTarget](https://www.techtarget.com/searchsoftwarequality/tip/Code-comment-best-practices-every-developer-should-know)
5. **Active voice preferred** - [UNT Technical Writing](https://techcomm.unt.edu/news/tips-using-plain-language-technical-communication.html)

## Implementation

When invoked:

1. Parse $ARGUMENTS for file patterns
2. Use Glob to find matching files
3. For each file:
   - Read content
   - Scan for patterns using regex/heuristics
   - Generate rewrite suggestions
   - Present to user with before/after
4. Wait for user approval
5. Apply changes with Edit tool

Flag high-confidence (obvious) vs low-confidence (stylistic) changes.
