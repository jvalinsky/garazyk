/**
 * Render Commands
 *
 * Defines pure data primitives for rendering UI elements. These commands decouple
 * layout math and component definitions from the rasterization step.
 *
 * @module tui/command
 */

import type { CellStyle } from "./renderer.ts";

/** A 2D rectangular bounding box. */
export interface BoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Renders a string of text within a bounding box. */
export interface TextCommand {
  type: "text";
  x: number;
  y: number;
  text: string;
  style?: CellStyle;
  clip?: BoundingBox;
}

/** Fills a rectangular region with a single character. */
export interface RectCommand {
  type: "rect";
  box: BoundingBox;
  char: string;
  style?: CellStyle;
  clip?: BoundingBox;
}

/** Draws a line-drawing border around a rectangular region. */
export interface BoxCommand {
  type: "box";
  box: BoundingBox;
  style?: CellStyle;
  title?: string;
  focused?: boolean;
  clip?: BoundingBox;
}

/** Scrollable content container with nested commands and viewport offset. */
export interface ScrollBoxCommand {
  type: "scrollbox";
  box: BoundingBox;
  content: RenderCommand[];
  scrollOffset: number;
  totalHeight: number;
  clip?: BoundingBox;
}

/** A pure rendering primitive. */
export type RenderCommand =
  | TextCommand
  | RectCommand
  | BoxCommand
  | ScrollBoxCommand;

/**
 * Rasterizes a list of render commands onto a ScreenBuffer.
 * This is the sole boundary where pure data commands become terminal cell mutations.
 *
 * Handles all command types including nested ScrollBoxCommand, which applies
 * scroll offset and clips child commands to the scrollbox viewport.
 */
export function rasterize(commands: RenderCommand[], buffer: {
  write(x: number, y: number, text: string, style?: CellStyle): void;
  writeClipped(
    x: number,
    y: number,
    text: string,
    style?: CellStyle,
    clip?: { x: number; y: number; width: number; height: number },
  ): void;
  fillRect(
    x: number,
    y: number,
    w: number,
    h: number,
    char: string,
    style?: CellStyle,
  ): void;
  fillRectClipped(
    x: number,
    y: number,
    w: number,
    h: number,
    char: string,
    style?: CellStyle,
    clip?: BoundingBox,
  ): void;
  box(
    x: number,
    y: number,
    w: number,
    h: number,
    style?: CellStyle,
    focused?: boolean,
  ): void;
  boxTitle(
    x: number,
    y: number,
    w: number,
    title: string,
    style?: CellStyle,
  ): void;
  boxClipped(
    x: number,
    y: number,
    w: number,
    h: number,
    style?: CellStyle,
    focused?: boolean,
    clip?: BoundingBox,
  ): void;
}): void {
  for (const cmd of commands) {
    switch (cmd.type) {
      case "text":
        if (cmd.clip) {
          buffer.writeClipped(cmd.x, cmd.y, cmd.text, cmd.style, cmd.clip);
        } else {
          buffer.write(cmd.x, cmd.y, cmd.text, cmd.style);
        }
        break;
      case "rect":
        buffer.fillRectClipped(
          cmd.box.x,
          cmd.box.y,
          cmd.box.width,
          cmd.box.height,
          cmd.char,
          cmd.style,
          cmd.clip,
        );
        break;
      case "box":
        if (cmd.clip) {
          buffer.boxClipped(
            cmd.box.x,
            cmd.box.y,
            cmd.box.width,
            cmd.box.height,
            cmd.style,
            cmd.focused,
            cmd.clip,
          );
        } else {
          buffer.box(
            cmd.box.x,
            cmd.box.y,
            cmd.box.width,
            cmd.box.height,
            cmd.style,
            cmd.focused,
          );
        }
        if (cmd.title) {
          buffer.boxTitle(
            cmd.box.x,
            cmd.box.y,
            cmd.box.width,
            cmd.title,
            cmd.style,
          );
        }
        break;
      case "scrollbox": {
        // Translate child commands by scroll offset and the scrollbox's own position,
        // then clip to the scrollbox viewport (intersected with any existing child clip).
        const scrollClip = cmd.clip ?? cmd.box;
        for (const subCmd of cmd.content) {
          const translated = translateCommand(subCmd, cmd.box.x, cmd.box.y - cmd.scrollOffset);
          const clipped = applyClipIntersection(translated, scrollClip);
          rasterize([clipped], buffer);
        }
        break;
      }
    }
  }
}

/**
 * Apply a clip region to a command, intersecting with any existing child clip.
 * If the child has no clip, the parent clip is used directly.
 * If the child already has a clip, the intersection of child and parent is used.
 */
function applyClipIntersection(
  cmd: RenderCommand,
  parentClip: BoundingBox,
): RenderCommand {
  if (!cmd.clip) return { ...cmd, clip: parentClip };
  return { ...cmd, clip: intersectBox(cmd.clip, parentClip) };
}

/**
 * Compute the intersection of two bounding boxes.
 * Returns a box with zero width/height if they don't overlap.
 */
function intersectBox(a: BoundingBox, b: BoundingBox): BoundingBox {
  const x1 = Math.max(a.x, b.x);
  const y1 = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.width, b.x + b.width);
  const y2 = Math.min(a.y + a.height, b.y + b.height);
  return {
    x: x1,
    y: y1,
    width: Math.max(0, x2 - x1),
    height: Math.max(0, y2 - y1),
  };
}

/**
 * Translate a render command's coordinates by an offset.
 * Preserves clip regions (does not translate them).
 */
function translateCommand(
  cmd: RenderCommand,
  dx: number,
  dy: number,
): RenderCommand {
  switch (cmd.type) {
    case "text":
      return { ...cmd, x: cmd.x + dx, y: cmd.y + dy };
    case "rect":
      return {
        ...cmd,
        box: { ...cmd.box, x: cmd.box.x + dx, y: cmd.box.y + dy },
      };
    case "box":
      return {
        ...cmd,
        box: { ...cmd.box, x: cmd.box.x + dx, y: cmd.box.y + dy },
      };
    case "scrollbox":
      return {
        ...cmd,
        box: { ...cmd.box, x: cmd.box.x + dx, y: cmd.box.y + dy },
      };
  }
}
