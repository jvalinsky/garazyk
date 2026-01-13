# Chapter 11 Analysis: HTTP Server

## Issues

**Code-Heavy**: 80% code, 20% explanation
**Missing**: GCD explanation, async flow visualization, thread safety rationale, error handling patterns
**Assumed Knowledge**: GCD concepts, BSD sockets, weak/strong references, semaphores

## Key Improvements Needed

1. **Explain GCD from scratch** - event loop analogy, serial vs concurrent queues
2. **Visualize request flow** - ASCII sequence diagram
3. **Thread safety explanation** - why serial queue, why @synchronized
4. **Connection lifecycle** - state machine diagram
5. **Error patterns** - what errors can occur and how handled
6. **Exercises** - custom route handler, error middleware

## Analogies to Add

- GCD queues: Restaurant with order tickets
- Serial queue: Single-file line
- Weak references: Safety rope that lets go
- Keep-alive: Restaurant table you can reuse

## Estimated Time: 10-12 hours
