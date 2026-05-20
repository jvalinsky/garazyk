# Core Primitives

The base layer of the TUI abstracts away ANSI escape codes, binary input parsing, and keyboard navigation state.

## 1. Renderer (`renderer.ts`)

The renderer exposes a `ScreenBuffer` class that acts as a 2D grid of `Cell` elements.

### API Highlights
- `class ScreenBuffer`
  - `write(x, y, text, style?)`: Writes a string horizontally starting at `x,y`.
  - `fillRect(x, y, w, h, char, style?)`: Fills a region with a character.
  - `box(x, y, w, h, style?)`: Draws a line-drawing box.
  - `diff(otherBuffer)`: Returns the minimal ANSI string required to mutate the terminal to match this buffer.
- **Styling**: `fg(color)`, `bg(color)`, `bold()`, `dim()`, `reverse()`, `underline()`. Styles are bitmasks or structured objects merged via `mergeStyles()`.

## 2. Input Parsing (`input.ts`)

Converts raw VT100/ANSI byte sequences into structured `Key` objects.

### API Highlights
- `interface Key`: `{ name: string, ctrl: boolean, meta: boolean, shift: boolean }`
- `parseKey(bytes: number[]): [Key, number] | null`: Extracts one key and returns the number of bytes consumed. Handles multi-byte UTF-8, Arrow Keys, F-keys, and escape sequences.
- `isKey(key, name)`: Helper to assert key name.
- `isQuit(key)`: Helper to assert `Ctrl+C`, `Ctrl+D`, or `q`.

## 3. Focus Management (`focus.ts`)

Because there is no DOM, focus is managed by a standalone `FocusRing` class.

### API Highlights
- `class FocusRing<T>`
  - `constructor(items: T[])`
  - `next() / prev()`: Cycles focus.
  - `jump(item)`: Moves focus directly to an item.
  - `isFocused(item)`: Returns true if the item is currently active.