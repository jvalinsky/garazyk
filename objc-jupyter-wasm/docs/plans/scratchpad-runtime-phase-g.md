# Runtime Expansion Phase G: Message Forwarding & KVC

## Goal
Implement Objective-C message forwarding (`forwardInvocation:`) and basic Key-Value Coding (KVC).

## Design Choices
1. **Message Forwarding**:
    - Update `parse_message_send` to handle the case where a selector is not found.
    - If `methodSignatureForSelector:` returns a non-nil value (simulated marker), create an `NSInvocation` marker and pass it to `forwardInvocation:`.
    - This allows for dynamic proxying and other advanced ObjC patterns.

2. **Key-Value Coding (KVC)**:
    - Implement `valueForKey:` and `setValue:forKey:` as built-in methods in `objc_interp_messages.c`.
    - These will search the property table and then the ivar table for the specified key.
    - Support for "automatic" KVC for interpreter-defined classes.

## Task List
- [x] Implement `NSInvocation` marker and creation logic.
- [x] Update dispatch logic in `objc_interp_messages.c` to support the forwarding path.
- [x] Implement `valueForKey:` in `objc_interp_messages.c`.
- [x] Implement `setValue:forKey:` in `objc_interp_messages.c`.
- [x] Add tests for dynamic message forwarding and KVC property access.
- [x] Verify integration with `NSDictionary` (e.g., `dictionaryWithValuesForKeys:`).
