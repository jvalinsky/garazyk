# Runtime & State Bridge

The TUI runtime connects the stateless renderers to the stateful TEA (The Elm Architecture) core.

## The TUI Runtime (`runtime.ts`)

Instead of making direct HTTP calls like the Web UI, the original TUI runtime (`createTuiRuntime`) intercepts TEA `Cmd.fetch` objects.

### API Highlights
- `interface TuiRuntimeHandle`: `{ dispatch: (msg: Msg) => void, onChange: (cb: () => void) => void, destroy: () => void }`
- `createTuiRuntime(initialState)`: 
  - Initializes the TEA state.
  - Starts the 1-second tick timer.
  - Resolves `Cmd.fetch` pseudo-URLs to internal service method calls.

## Transition Notes

In recent commits, the TUI's internal `handleFetch` logic was unified with the Web UI to behave identically (using `@garazyk/gruszka` TransportLayer) rather than using the mocked `resolveServiceHandler` loop. This ensures the TUI and Web UI represent the exact same state transitions.

The `onChange` callback is what triggers the primary event loop to execute `renderView` and flush the `ScreenBuffer` diff to the terminal.