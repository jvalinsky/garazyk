# R1: Kernel Review (Light)

## Summary
The WASM kernel interpreter has several crash-prone pointer handling paths and JSON serialization correctness issues. The most impactful are invalid pointer dereferences in `isKindOfClass:`/`isMemberOfClass:` and broken JSON output from float/control-character handling.

## Findings

### HIGH — isKindOfClass:/isMemberOfClass: can dereference invalid pointer and trap WASM runtime
- **File**: objc-jupyter-wasm/kernel/objc_interp_messages.c
- **Description**: `isKindOfClass:` / `isMemberOfClass:` can fall back to `object_getClass((id)obj_deref(...))` for non-class arguments. If a user passes a plain string literal or other interpreter handle that is not an actual ObjC object, this dereferences an invalid pointer and traps the WASM runtime.
- **Impact**: WASM runtime crash from user code — denial of service in the Jupyter kernel.
- **Recommendation**: Harden the fallback so it only accepts known class markers or verified runtime class objects.

### HIGH — Float values serialized as literal "0.0" regardless of actual value
- **File**: objc-jupyter-wasm/kernel/objc_interp_messages.c
- **Description**: JSON serialization helpers write float values as the literal `0.0` regardless of their actual value.
- **Impact**: Silent data corruption — all float values in kernel output appear as 0.0.
- **Recommendation**: Fix float serialization to write the actual value using a minimal float-to-string converter.

### MEDIUM — JSON string emission doesn't escape control characters
- **File**: objc-jupyter-wasm/kernel/objc_interp_messages.c
- **Description**: `append_json_str()` only escapes `"` and `\`, but not control characters like `\n`, `\r`, `\t`, etc. Generated JSON can be invalid for ordinary strings containing these characters.
- **Impact**: Invalid JSON output from the kernel — downstream parsers will reject it.
- **Recommendation**: Replace the ad hoc JSON string emission with proper escaping for all control characters (U+0000 through U+001F).

### MEDIUM — Integer negation of INT_MIN is undefined behavior
- **File**: objc-jupyter-wasm/kernel/objc_interp_format.c
- **Description**: The formatting path has integer-sign edge cases (`-INT_MIN` / `-LONG_MIN`-style behavior) in helper routines, which is undefined in C.
- **Impact**: Undefined behavior — may produce incorrect output or crash on some platforms.
- **Recommendation**: Handle the INT_MIN edge case explicitly before negation.
