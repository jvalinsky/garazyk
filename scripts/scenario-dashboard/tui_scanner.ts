import type { ScreenBuffer, CellStyle } from "@garazyk/tui";
import type { ElementMeta, Rect, TuiElement, CharToken, CharTokenType, ElementAction } from "./tui_types.ts";

const CORNER_TOPLEFT     = new Set([0x250C, 0x250D, 0x250E, 0x250F, 0x2552, 0x2553, 0x2554, 0x256D]);
const CORNER_TOPRIGHT    = new Set([0x2510, 0x2511, 0x2512, 0x2513, 0x2555, 0x2556, 0x2557, 0x256E]);
const CORNER_BOTLEFT     = new Set([0x2514, 0x2515, 0x2516, 0x2517, 0x2558, 0x2559, 0x255A, 0x256F]);
const CORNER_BOTRIGHT    = new Set([0x2518, 0x2519, 0x251A, 0x251B, 0x255B, 0x255C, 0x255D, 0x2570]);
const TEE_LEFT           = new Set([0x251C, 0x251D, 0x251E, 0x251F, 0x2520, 0x2521, 0x2522, 0x2523, 0x255E, 0x255F, 0x2560]);
const TEE_RIGHT          = new Set([0x2524, 0x2525, 0x2526, 0x2527, 0x2528, 0x2529, 0x252A, 0x252B, 0x2561, 0x2562, 0x2563]);
const TEE_DOWN           = new Set([0x252C, 0x252D, 0x252E, 0x252F, 0x2530, 0x2531, 0x2532, 0x2533, 0x2564, 0x2565, 0x2566]);
const TEE_UP             = new Set([0x2534, 0x2535, 0x2536, 0x2537, 0x2538, 0x2539, 0x253A, 0x253B, 0x2567, 0x2568, 0x2569]);
const CROSS              = new Set([0x253C, 0x253D, 0x253E, 0x253F, 0x2540, 0x2541, 0x2542, 0x2543, 0x2544, 0x2545, 0x2546, 0x2547, 0x2548, 0x2549, 0x254A, 0x254B, 0x256A, 0x256B, 0x256C]);

const EDGE_HORIZONTAL    = new Set([0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509, 0x254C, 0x254D, 0x2550]);
const EDGE_VERTICAL      = new Set([0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B, 0x254E, 0x254F, 0x2551]);

export function classifyChar(charStr: string, style: CellStyle): CharTokenType {
  const cp = charStr.codePointAt(0) ?? 0x20;

  // Box drawing (U+2500-257F)
  if (cp >= 0x2500 && cp <= 0x257F) {
    if (CORNER_TOPLEFT.has(cp)) return "corner_tl";
    if (CORNER_TOPRIGHT.has(cp)) return "corner_tr";
    if (CORNER_BOTLEFT.has(cp)) return "corner_bl";
    if (CORNER_BOTRIGHT.has(cp)) return "corner_br";
    if (TEE_LEFT.has(cp)) return "tee_l";
    if (TEE_RIGHT.has(cp)) return "tee_r";
    if (TEE_DOWN.has(cp)) return "tee_d";
    if (TEE_UP.has(cp)) return "tee_u";
    if (CROSS.has(cp)) return "cross";
    if (EDGE_HORIZONTAL.has(cp)) return "edge_h";
    if (EDGE_VERTICAL.has(cp)) return "edge_v";
  }

  // Block elements (U+2580-259F)
  if (cp >= 0x2580 && cp <= 0x259F) {
    if (cp == 0x2588) return "block_full";          // █
    if (cp == 0x258C || cp == 0x258E) return "block_full";  // ▌▎
    if (cp == 0x2590) return "block_full";        // ▐
    if (cp >= 0x2591 && cp <= 0x2593) {              // ░▒▓
      return cp == 0x2591 ? "shade_light"
           : cp == 0x2592 ? "shade_med"
           : "shade_dark";
    }
    return "block_full"; // fallback for other blocks
  }

  // Geometric shapes (U+25A0-25FF)
  if (cp >= 0x25A0 && cp <= 0x25FF) {
    if (cp == 0x25CF) return "radio_on";           // ●
    if (cp == 0x25CB) return "radio_off";          // ○
    if (cp == 0x25C9 || cp == 0x25CE) return "radio_on"; // ◉ ◎
    if (cp == 0x25A0 || cp == 0x25A1) {            // ■□
      return cp == 0x25A0 ? "bullet" : "radio_off";
    }
    if (cp == 0x25B6 || cp == 0x25B8) return "expand_collapsed";  // ▶▸
    if (cp == 0x25BC || cp == 0x25BE) return "expand_expanded";   // ▼▾
    if (cp == 0x25C6 || cp == 0x25C7 || cp == 0x25AA || cp == 0x25AB) return "bullet"; // ◆◇▪▫
    if (cp == 0x25B2) return "scroll_up"; // ▲
  }

  // Checkboxes (U+2610-2612)
  if (cp == 0x2610) return "checkbox_off";       // ☐
  if (cp == 0x2611) return "checkbox_on";        // ☑
  if (cp == 0x2612) return "checkbox_off";     // ☒ (treating mixed as off for extraction)

  // Arrows (U+2190-21FF)
  if (cp >= 0x2190 && cp <= 0x21FF) {
    if (cp == 0x2191) return "scroll_up";    // ↑
    if (cp == 0x2193) return "scroll_down";  // ↓
  }

  return cp == 0x20 ? "whitespace" : "text";
}

export function classifyBuffer(buffer: ScreenBuffer): CharToken[][] {
  const result: CharToken[][] = [];
  for (let y = 0; y < buffer.height; y++) {
    const row: CharToken[] = [];
    for (let x = 0; x < buffer.width; x++) {
      const cell = buffer.getCell(x, y);
      if (!cell) {
        row.push({
          type: "whitespace",
          char: " ",
          cp: 0x20,
          style: { fg: undefined, bg: undefined, bold: false, underline: false, inverse: false },
          weight: "light",
        });
        continue;
      }
      
      let type = classifyChar(cell.char, cell.style);
      
      row.push({
        type,
        char: cell.char,
        cp: cell.char.codePointAt(0) ?? 0x20,
        style: {
          fg: cell.style.fg >= 0 ? cell.style.fg.toString() : undefined,
          bg: cell.style.bg >= 0 ? cell.style.bg.toString() : undefined,
          bold: cell.style.bold,
          underline: cell.style.underline,
          inverse: cell.style.reverse,
        },
        weight: "light", // simplified for now
      });
    }
    result.push(row);
  }
  return result;
}

export function findContainers(tokens: CharToken[][]): Rect[] {
  const rects: Rect[] = [];
  const height = tokens.length;
  if (height === 0) return rects;
  const width = tokens[0]!.length;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const tl = tokens[y]![x]!.type;
      if (tl === "corner_tl" || tl === "tee_l" || tl === "tee_d" || tl === "cross") {
        // Find all possible right edges
        const validRights: number[] = [];
        let rightX = x + 1;
        while (rightX < width) {
          const t = tokens[y]![rightX]!.type;
          if (t === "corner_tr" || t === "tee_d" || t === "cross" || t === "tee_r") {
            validRights.push(rightX);
          }
          if (t !== "edge_h" && t !== "tee_u" && t !== "tee_d" && t !== "cross" && t !== "tee_r" && t !== "corner_tr") {
             break;
          }
          rightX++;
        }
        
        // Find all possible bottom edges
        const validBottoms: number[] = [];
        let bottomY = y + 1;
        while (bottomY < height) {
          const t = tokens[bottomY]![x]!.type;
          if (t === "corner_bl" || t === "tee_l" || t === "cross" || t === "tee_d" || t === "tee_u") {
            validBottoms.push(bottomY);
          }
          if (t !== "edge_v" && t !== "tee_r" && t !== "tee_l" && t !== "cross" && t !== "tee_d" && t !== "corner_bl" && t !== "tee_u") {
            break;
          }
          bottomY++;
        }
        
        // Check intersections
        for (const rX of validRights) {
          for (const bY of validBottoms) {
            const br = tokens[bY]![rX]!.type;
            if (br === "corner_br" || br === "tee_l" || br === "tee_r" || br === "tee_u" || br === "tee_d" || br === "cross") {
              rects.push({
                x, y, width: rX - x + 1, height: bY - y + 1
              });
            }
          }
        }
      }
    }
  }

  // Sort by area descending
  rects.sort((a, b) => (b.width * b.height) - (a.width * a.height));
  return rects;
}

export interface DetectedElement {
  type: TuiElement["type"];
  bounds: Rect;
  role: string;
  content: string;
  children: DetectedElement[];
  interactable: boolean;
}

function rectContains(outer: Rect, inner: Rect): boolean {
  return inner.x >= outer.x && inner.y >= outer.y &&
         (inner.x + inner.width) <= (outer.x + outer.width) &&
         (inner.y + inner.height) <= (outer.y + outer.height);
}

export function extractTree(buffer: ScreenBuffer, metaMap?: Map<string, ElementMeta>): TuiElement {
  const tokens = classifyBuffer(buffer);
  const containers = findContainers(tokens);
  
  // Basic Layer 2 element extraction (fallback to containers if no meta map matches)
  const rootElements: DetectedElement[] = [];
  
  // Layer 1 override mapping
  const elementsByRef = new Map<string, TuiElement>();
  
  if (metaMap) {
    for (const [ref, meta] of metaMap.entries()) {
      const el: TuiElement = {
        type: meta.role as any, // fallback
        role: meta.role,
        bounds: meta.bounds,
        content: meta.content,
        label: meta.label,
        interactable: meta.interactable,
        focused: meta.focused,
        actions: meta.actions.map(a => ({ type: a } as any)),
        id: ref,
        states: meta.states,
        style: { bold: false, underline: false, inverse: false },
        children: []
      };
      
      if (meta.role === "panel") el.type = "container";
      if (meta.role === "service" || meta.role === "scenario") el.type = "list";
      if (meta.role === "heading") el.type = "heading";
      if (meta.role === "help" || meta.role === "detail") el.type = "text";
      
      elementsByRef.set(ref, el);
    }
  }
  
  // Create Layer 2 containers that don't match Layer 1
  for (const c of containers) {
    let matched = false;
    for (const el of elementsByRef.values()) {
      if (el.bounds.x === c.x && el.bounds.y === c.y && el.bounds.width === c.width && el.bounds.height === c.height) {
        matched = true;
        break;
      }
    }
    if (!matched) {
       // Layer 2 container fallback
       const el: TuiElement = {
         type: "container",
         role: "container",
         bounds: c,
         interactable: false,
         focused: false,
         actions: [],
         id: `layer2_${c.x}_${c.y}_${c.width}_${c.height}`,
         states: [],
         style: { bold: false, underline: false, inverse: false },
         children: []
       };
       
       // Table heuristic: contains 'cross' (┼) inside bounds
       let hasCross = false;
       for (let cy = c.y + 1; cy < c.y + c.height - 1; cy++) {
         for (let cx = c.x + 1; cx < c.x + c.width - 1; cx++) {
           if (tokens[cy]![cx]!.type === "cross") {
             hasCross = true;
             break;
           }
         }
         if (hasCross) break;
       }
       
       if (hasCross) {
         el.type = "table";
         el.role = "table";
       } else {
         // List heuristic: contains multiple 'bullet' or '•' at the same x offset
         let bulletCount = 0;
         for (let cy = c.y + 1; cy < c.y + c.height - 1; cy++) {
           for (let cx = c.x + 1; cx < c.x + c.width - 1; cx++) {
             const t = tokens[cy]![cx]!;
             if (t.type === "bullet" || t.char === "-" || t.char === "*" || t.char === "•") {
               bulletCount++;
               break; // count lines with bullet
             }
           }
         }
         if (bulletCount >= 2) {
           el.type = "list";
           el.role = "list";
         }
       }
       
       elementsByRef.set(el.id, el);
    }
  }

  // Layer 2 Interactive elements detection
  for (let y = 0; y < buffer.height; y++) {
    let x = 0;
    while (x < buffer.width - 2) {
      const t1 = tokens[y]![x]!.char;
      const t2 = tokens[y]![x+1]!.char;
      const t3 = tokens[y]![x+2]!.char;
      
      if (t1 === '[' && (t2 === ' ' || t2 === 'X' || t2 === 'x') && t3 === ']') {
        const id = `layer2_checkbox_${x}_${y}`;
        elementsByRef.set(id, {
          type: "checkbox", role: "checkbox", bounds: { x, y, width: 3, height: 1 },
          interactable: true, focused: false, actions: ["click" as ElementAction], id, states: [t2 === ' ' ? "unchecked" : "checked"],
          style: { bold: false, underline: false, inverse: false }, children: []
        });
        x += 3;
        continue;
      }
      
      if (t1 === '(' && (t2 === ' ' || t2 === '*') && t3 === ')') {
        const id = `layer2_radio_${x}_${y}`;
        elementsByRef.set(id, {
          type: "radio", role: "radio", bounds: { x, y, width: 3, height: 1 },
          interactable: true, focused: false, actions: ["click" as ElementAction], id, states: [t2 === ' ' ? "unchecked" : "checked"],
          style: { bold: false, underline: false, inverse: false }, children: []
        });
        x += 3;
        continue;
      }
      
      if (t1 === '<') {
        let endX = x + 1;
        let content = "";
        while (endX < buffer.width && tokens[y]![endX]!.char !== '>') {
          content += tokens[y]![endX]!.char;
          endX++;
        }
        if (endX < buffer.width && tokens[y]![endX]!.char === '>' && content.trim().length > 0) {
          const id = `layer2_button_${x}_${y}`;
          elementsByRef.set(id, {
            type: "button", role: "button", bounds: { x, y, width: endX - x + 1, height: 1 },
            interactable: true, focused: false, actions: ["click" as ElementAction], id, states: [], content, label: content.trim(),
            style: { bold: false, underline: false, inverse: false }, children: []
          });
          x = endX + 1;
          continue;
        }
      }
      x++;
    }
  }
  
  // Build hierarchy based on containment
  const sortedRefs = Array.from(elementsByRef.values()).sort((a, b) => {
    return (b.bounds.width * b.bounds.height) - (a.bounds.width * a.bounds.height);
  });
  
  const root = {
    type: "container" as const,
    role: "application",
    bounds: { x: 0, y: 0, width: buffer.width, height: buffer.height },
    interactable: false,
    focused: false,
    actions: [],
    id: "root",
    states: [],
    style: { bold: false, underline: false, inverse: false },
    children: [] as TuiElement[]
  };
  
  for (const el of sortedRefs) {
    // Find smallest parent
    let parent: TuiElement = root;
    for (const potential of sortedRefs) {
      if (potential === el) continue;
      if (rectContains(potential.bounds, el.bounds)) {
        if (parent === root || (potential.bounds.width * potential.bounds.height < parent.bounds.width * parent.bounds.height)) {
          parent = potential;
        }
      }
    }
    parent.children.push(el);
  }

  // Assign cursor position
  // Extract text content for elements that don't have it defined
  
  return root;
}
