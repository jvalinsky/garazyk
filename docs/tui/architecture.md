# TUI Architecture & Event Loop

The custom TUI operates on an **Immediate-Mode Rendering** paradigm, bridging terminal events directly with the pure-functional TEA (The Elm Architecture) state model defined in `dashboard_state.ts`.

## The Event Loop

The primary event loop (in `tui.ts`) manages non-blocking reads from `Deno.stdin` and syncs with the TEA runtime.

1. **Initialization**:
   - Save the terminal state and switch to Alternate Screen buffer (`\x1b[?1049h`).
   - Hide the cursor and disable terminal echo.
   - Attach listeners for `SIGWINCH` (resize) and `SIGTSTP` (suspend).

2. **Read Loop**:
   An async generator `readKeys()` continuously yields `Key` objects parsed from raw terminal bytes.

3. **Event Handling**:
   ```mermaid
   graph TD
     A[Raw Bytes from Deno.stdin] --> B(parseKey)
     B --> C{Key Event}
     C -->|Ctrl+C| D[Exit]
     C -->|Tab / Shift+Tab| E[FocusRing.next / prev]
     C -->|Directional| F[Panel Scrolling]
     C -->|Enter / 's'| G[Dispatch TEA Message]
     G --> H[Update Dashboard State]
     H --> I(renderView)
     I --> J[ScreenBuffer Diff]
     J --> K[Write ANSI to Deno.stdout]
   ```

4. **Cleanup**:
   A `finally` block ensures `exitTerminalMode()` is always called, restoring the terminal cursor and main buffer, even on uncaught exceptions.

## Single-Pass View Generation

Because the state is pure, the UI is stateless. The `renderView(buffer, state, layout, focusRing)` function simply walks the component tree, calculating static coordinates and executing `buffer.write(x, y, ...)` or `buffer.fillRect(...)` calls. 

No component instances are retained in memory between frames.