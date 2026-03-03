# Diagram Quick Reference

A condensed guide to all diagrams available in this project.

## Available Diagram Files

| File | Type | Purpose |
|------|------|---------|
| `ARCHITECTURE_DIAGRAMS.md` | Mermaid | System overview, flows, sequences |
| `DIAGRAMS_MERMAID.md` | Mermaid | ATProto-specific protocols & models |
| `DEVELOPMENT_WORKFLOWS.md` | Mermaid | Dev processes, debugging, testing |
| `high_level_architecture.dot` | Graphviz | Full system architecture |
| `request_flow.dot` | Graphviz | HTTP request pipeline |
| `database_schema.dot` | Graphviz | SQLite schema relationships |
| `authentication_flow.dot` | Graphviz | Auth process (JWT, OAuth, 2FA) |
| `repository_engine.dot` | Graphviz | MST/CAR content-addressable storage |
| `firehose_sync.dot` | Graphviz | Real-time event streaming |
| `module_dependencies.dot` | Graphviz | Inter-module dependencies |
| `request_flow.dot` | Graphviz | API request handling |

## Diagram by Use Case

### Understanding the System
```
Start with: ARCHITECTURE_DIAGRAMS.md
→ high_level_architecture.dot
→ module_dependencies.dot
```

### Working with ATProto Protocols
```
Start with: DIAGRAMS_MERMAID.md
→ XRPC protocol flows
→ Repository operations
→ OAuth2 sequence
```

### Development Tasks
```
Start with: DEVELOPMENT_WORKFLOWS.md
→ Build and run process
→ Test pyramid
→ Debugging flowchart
```

### Database Work
```
Start with: database_schema.dot
→ Check entity relationships
→ Understand transactions
```

### Authentication
```
Start with: authentication_flow.dot
→ JWT token flow
→ Session management
→ OAuth2 process
```

## Quick Diagram Selection

```mermaid
flowchart TD
    A[What do you need?] --> B[Protocol interaction]
    A --> C[Data model]
    A --> D[Control flow]
    A --> E[System architecture]
    A --> F[Development process]
    
    B --> B1[Use sequenceDiagram]
    C --> C1[Use classDiagram]
    D --> D1[Use flowchart TD]
    E --> E1[Use graph TB or dot]
    F --> F1[Use flowchart TD]
    
    B1 --> G[Mermaid or Graphviz]
    C1 --> G
    D1 --> G
    E1 --> G
    F1 --> G
    
    style A fill:#c8e6c9
```

## Generate Graphviz Diagrams

```bash
cd docs/architecture

# Generate all as PNG
for f in *.dot; do
    name="${f%.dot}"
    dot -Tpng "$f" -o "${name}.png"
done

# Generate as SVG (better quality)
dot -Tsvg "$f" -o "${name}.svg"
```

## Diagram Color Legend

| Color | Meaning | Hex |
|-------|---------|-----|
| Green | Start/End/Success | #c8e6c9 |
| Blue | Processes/Actions | #bbdefb |
| Orange | Decisions/Checks | #ffe0b2 |
| Red | Errors/Failures | #ffcdd2 |
| Yellow | Data/Tokens | #fff9c4 |

## Common Patterns

### Sequence Diagram (Timing)
```mermaid
sequenceDiagram
    participant A
    participant B
    A->>B: Request
    B-->>A: Response
```

### Class Diagram (Data)
```mermaid
classDiagram
    class A { +field }
    class B { +field }
    A --> B : relation
```

### Flowchart (Logic)
```mermaid
flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action]
    B -->|No| D[Other]
    C --> E[End]
    D --> E
```

### Architecture (Components)
```mermaid
graph TB
    subgraph "Layer 1"
        A[Component A]
    end
    subgraph "Layer 2"
        B[Component B]
    end
    A --> B
```

## Adding New Diagrams

When adding diagrams:

1. **Choose the right type** - Match diagram to purpose
2. **Keep it simple** - One concept per diagram
3. **Use consistent colors** - Follow the color legend
4. **Label clearly** - Descriptive node names
5. **Add to this file** - Reference in quick navigation

### Example: Adding a New Protocol Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    
    C->>S: New operation
    S-->>C: Response
```

Add to: `docs/architecture/DIAGRAMS_MERMAID.md`

## Related Documentation

### Architecture Documents
- [README.md](README.md) - Architecture documentation index
- [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) - Component analysis for diagram context

### Diagram Documents
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS.md) - System overview diagrams
- [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID.md) - Protocol flow diagrams
- [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS.md) - Development process diagrams
