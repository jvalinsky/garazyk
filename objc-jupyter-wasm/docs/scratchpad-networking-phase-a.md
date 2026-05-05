# Phase A Scratchpad: NSJSONSerialization Bridge

## Goal
Implement `NSJSONSerialization` in the Objective-C WASM interpreter by bridging to the host's native `JSON.parse` and `JSON.stringify`.

## Design Choices
1. **Host-Driven**: Use `objc_kernel_host` imports for JSON processing to leverage browser performance and avoid bloating the WASM binary with a C JSON library.
2. **Handle-Based Exchange**: 
   - `json_parse` will return an identifier that maps to a collection in the interpreter.
   - Since our interpreter already has a collection system (`FDObj:NSArr:N`, `FDObj:NSDict:N`), we can directly populate these tables.
3. **Data Representation**:
   - `NSData` is currently represented as a marker `FDObj:NSData:N` pointing to a byte buffer in the side table.
   - `JSONObjectWithData` will take this buffer, send it to JS as a string, get back a JSON object, and then the JS-WASM bridge will recursively build `NSDictionary`/`NSArray` markers.

## Task List
- [x] Define host imports in `objc_interpreter.c` (actually in `objc_interp_state.c`)
- [x] Implement host functions in `js/wasm-loader.js` and `tests/test-json-bridge.mjs`
- [x] Implement `+JSONObjectWithData:options:error:` in `objc_interp_messages.c`
- [x] Decide on `+dataWithJSONObject:options:error:` approach (Implementing in C is simpler than cross-boundary JS traversal).
- [x] Implement `+dataWithJSONObject:options:error:` in `objc_interp_messages.c`
- [x] Verification test case for stringification
