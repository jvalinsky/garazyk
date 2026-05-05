# Phase B Scratchpad: Async Networking Loop

## Goal
Bridge `NSURLSession` to the browser's `fetch()` API, enabling asynchronous HTTP requests with block-based completion handlers.

## Design Choices
1. **Task Registry**: The kernel needs to remember which completion block corresponds to which fetch request. We'll add a `PendingNetworkTask` struct and a table to the global context.
2. **Host Bridge**:
   - `objc_kernel_host_fetch`: Called by WASM to initiate a fetch. Passes URL, method, headers (as JSON string), and body data. Returns a task ID.
   - `objc_kernel_on_fetch_complete`: Exported from WASM, called by JS when the fetch promise resolves. Passes task ID, HTTP status code, and response data.
3. **Foundation Stubs**:
   - `NSURL`: Store the URL string.
   - `NSMutableURLRequest`: Store URL, HTTP method, headers (in a dictionary), and body (NSData).
   - `NSURLSession`: Handle `dataTaskWithRequest:completionHandler:` and `resume`.

## Task List
- [x] Define `PendingNetworkTask` and registry in `kernel/objc_interp_types.h` / `kernel/objc_interp_context.h`.
- [x] Define `objc_kernel_host_fetch` import in `kernel/objc_interp_state.c`.
- [x] Implement `objc_kernel_on_fetch_complete` export in `kernel/objc_interp_state.c`.
- [x] Implement JS `fetch` handler in `js/wasm-loader.js`.
- [x] Implement `NSURL`, `NSMutableURLRequest`, `NSURLSession`, `NSURLSessionDataTask` in `kernel/objc_interp_messages.c`.
- [x] Handle block execution on fetch completion.
- [x] Add `test-network.mjs` to verify.
