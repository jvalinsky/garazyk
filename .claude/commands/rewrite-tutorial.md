---
description: Rewrite tutorial chapters with pedagogical best practices
allowed-tools: Read, Write, Glob
argument-hint: <tutorial-file-path>
---

# Tutorial Rewriting Skill

This skill rewrites tutorial chapters to be more pedagogically sound, assuming zero prior knowledge and building concepts incrementally.

## Core Principles

### 1. Zero-Knowledge Assumption
- Assume the reader knows NOTHING about the topic
- Define every term before using it
- Build from first principles
- Connect to concepts the reader already knows from daily life

### 2. Explain Before Showing
- Start with the problem or need
- Explain what you're about to build and WHY
- Walk through the solution conceptually
- THEN show the code
- Explain each significant line or block

### 3. Incremental Complexity
- Start with the simplest possible version
- Add one concept at a time
- Show evolution from simple → complex
- Explain what changed and why

### 4. Active Learning
- Use analogies and metaphors
- Include thought experiments
- Pose questions to the reader
- Provide exercises that build understanding
- Show common mistakes and why they happen

### 5. Code Explanation Pattern
For every code block:
1. State what this code accomplishes (the goal)
2. Break down the approach (the strategy)
3. Explain key lines or sections (the implementation)
4. Highlight important details (gotchas, edge cases, design choices)

## Rewriting Process

### Step 1: Read the Original Tutorial
```bash
# Read the file specified in $ARGUMENTS
```

### Step 2: Analyze Structure
Identify:
- What concepts are assumed but not explained
- Where code is shown without sufficient explanation
- Missing motivation (the "why")
- Gaps in incremental progression
- Places where examples would help

### Step 3: Create Rewrite Plan
Before rewriting, outline:
1. What prerequisite knowledge needs explanation
2. The progression of concepts (simple → complex)
3. Where to add analogies or examples
4. Which code blocks need deeper explanation
5. What exercises would reinforce understanding

### Step 4: Rewrite with Enhanced Pedagogy

Use this structure for each major concept:

#### Introduce the Need
"Imagine you want to [real-world goal]. To do this, you need [concept]."

#### Build Intuition
"Think of [concept] like [familiar analogy]. Just as [familiar thing does X], [concept does Y]."

#### Show the Simplest Version
"Let's start with the most basic version. Here's what it looks like:
```code
// Simplest possible implementation
```
This works because [explanation]."

#### Explain the Progression
"Now let's add [next feature] to handle [real need]:
```code
// Enhanced version
```
Notice how we added [specific change]. This is important because [reason]."

#### Explain Production Code
"In the actual codebase, we need to handle [additional concerns]. Here's the full implementation:
```code
// Production code
```

Let's break this down:
- Line X: [what it does and why]
- Lines Y-Z: [what this block accomplishes]
- The pattern of [technique]: [why we use it]"

#### Common Pitfalls
"You might be tempted to [common mistake]. Here's why that doesn't work:
[Explanation with example]

Instead, we [correct approach] because [reason]."

#### Exercises
"To reinforce your understanding:
1. [Simple modification exercise]
2. [Conceptual question]
3. [Build something small using this concept]"

### Step 5: Preserve Technical Accuracy
- Keep all code examples correct
- Maintain references to actual source files
- Don't simplify away important details
- Verify technical claims

### Step 6: Enhance Formatting
Use:
- ✅ / ❌ for do's and don'ts
- 💡 for key insights
- ⚠️ for important warnings
- 📝 for exercises
- 🔍 for deep dives into specific topics

Use tables for:
- Comparing approaches
- Listing components and their purposes
- Showing before/after

Use code comments generously:
```objc
// Not just what, but WHY
NSData *hash = [CID rawSha256:data];  // Always hash before signing
```

## Example Transformation

### BEFORE (Code-Heavy):
```
## Varint Encoding

Numbers in CIDs use varint encoding:

```objc
+ (NSData *)encodeVarint:(uint64_t)value {
    NSMutableData *data = [NSMutableData dataWithCapacity:9];
    uint64_t v = value;
    do {
        uint8_t byte = v & 0x7F;
        v >>= 7;
        if (v != 0) {
            byte |= 0x80;
        }
        [data appendBytes:&byte length:1];
    } while (v != 0);
    return [data copy];
}
```
```

### AFTER (Pedagogically Enhanced):
```
## Variable-Length Integers: Making CIDs Smaller

### The Problem

CIDs contain several numbers: version (usually 1), codec (like 0x71), and hash algorithm (like 0x12). We could store each as a fixed 4-byte integer, but that's wasteful—most values are tiny!

### The Solution: Varint Encoding

**Varint** (variable-length integer) uses only as many bytes as needed:
- Small numbers (0-127): 1 byte
- Larger numbers: Multiple bytes

Think of it like writing numbers in scientific notation—we only use more digits when we need them.

### How It Works

Each byte in a varint has two parts:
1. **7 bits for data** (stores part of the number)
2. **1 bit for "more to come"** (is this the last byte?)

Here's the encoding strategy:
```
Value 127 = 0x7F:      [0111 1111]  ← High bit is 0, so this is the last byte
Value 128 = 0x80:      [1000 0000] [0000 0001]  ← First byte has high bit 1
                        ↑ more coming
```

### The Implementation

Now let's see how to encode a number as varint:

```objc
+ (NSData *)encodeVarint:(uint64_t)value {
    NSMutableData *data = [NSMutableData dataWithCapacity:9];  // Max 9 bytes for 64-bit number
    uint64_t v = value;

    do {
        uint8_t byte = v & 0x7F;  // Take the lowest 7 bits
        v >>= 7;                   // Shift right by 7 (move to next 7 bits)

        if (v != 0) {              // Are there more bits to encode?
            byte |= 0x80;          // Set the "continuation" bit
        }

        [data appendBytes:&byte length:1];
    } while (v != 0);              // Keep going until all bits are encoded

    return [data copy];
}
```

**Line-by-line breakdown:**

1. `v & 0x7F` - Extract the rightmost 7 bits (binary: 0111 1111)
2. `v >>= 7` - Shift right by 7 bits to process the next chunk
3. `byte |= 0x80` - Set the high bit to 1 (binary: 1000 0000) to signal "more bytes follow"
4. Loop until `v` becomes 0 (all bits processed)

### Visualizing the Process

Let's encode the number 300:

```
300 in binary: 0000 0001 0010 1100

Step 1: Take lowest 7 bits: 010 1100 = 0x2C
        Remaining: 10 (not zero, so set continuation bit)
        Output byte: 1010 1100 = 0xAC

Step 2: Take next 7 bits: 000 0010 = 0x02
        Remaining: 0 (done! No continuation bit)
        Output byte: 0000 0010 = 0x02

Result: [0xAC, 0x02]
```

💡 **Why this matters for CIDs:** By using varints, a CID with version=1 and codec=0x71 only needs 2 bytes instead of 8 for these fields!

📝 **Exercise:** What would the varint encoding be for:
1. The number 1 (hint: fits in 7 bits)
2. The number 128 (hint: needs more than 7 bits)
3. Why is the maximum size 9 bytes for a 64-bit number? (hint: 7 bits per byte, how many bytes for 64 bits?)
```

## Quality Checklist

Before completing the rewrite, verify:

- [ ] Every technical term is defined before use
- [ ] Code blocks have explanatory text before AND after
- [ ] At least one analogy for each major concept
- [ ] Progression from simple to complex is clear
- [ ] Common mistakes are addressed
- [ ] Exercises reinforce key concepts
- [ ] No assumed knowledge beyond stated prerequisites
- [ ] Visual aids (tables, diagrams via text/ascii) are used
- [ ] File references and code accuracy preserved

## Output

Write the rewritten tutorial to a new file named:
`<original-name>-rewritten.md`

Then provide a summary of:
1. Key pedagogical improvements made
2. Concepts that were explained more thoroughly
3. Areas where more work might be needed

## Now Process: $ARGUMENTS

Read the tutorial file at the path provided in $ARGUMENTS, then rewrite it following all the principles above.
