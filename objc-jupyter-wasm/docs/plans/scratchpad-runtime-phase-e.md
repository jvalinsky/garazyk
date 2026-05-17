# Runtime Expansion Phase E: Property Attributes & Autoreleasepool

## Goal

Implement `@autoreleasepool` and extend `@property` to support standard attributes (nonatomic,
assign, etc.).

## Design Choices

1. **Autorelease Scaffolding**: Implement the structural `@autoreleasepool { ... }` as described in
   `docs/plan-autoreleasepool.md`. Even though the interpreter doesn't do real reference counting,
   having the scaffolding allows code to run unmodified.
2. **Attribute Parsing**: Update the property parser to recognize `nonatomic`, `assign`, `copy`,
   `strong`, `readonly`, etc.
3. **Storage Mapping**: Map attributes to internal behavior:
   - `readonly`: Suppress automatic setter synthesis.
   - `assign`/`strong`/`copy`: Currently treated as same (marker storage), but stored for
     reflection/inspection.
4. **Integration with `objc_kernel_inspect`**: Expose property attributes via the inspection API so
   the UI can show them.

## Task List

- [x] Implement `@autoreleasepool` (Phase 1-5 of `docs/plan-autoreleasepool.md`).
- [x] Update `parse_interface` in `objc_interp_class.c` to parse property attributes in parentheses.
- [x] Store attributes in `PropertyDecl` in `kernel/objc_interp_types.h`.
- [x] Update `parse_implementation` to respect `readonly` attribute during synthesis.
- [x] Add `autorelease` selector handler in `objc_interp_messages.c`.
- [x] Verify with tests and dot-syntax property access.
