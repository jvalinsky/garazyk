export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type SemanticRole =
  | "panel"
  | "statusBar"
  | "table"
  | "list"
  | "progressBar"
  | "button"
  | "checkbox"
  | "radio"
  | "input"
  | "heading"
  | "scrollbar"
  | "tabBar"
  | "help"
  | "service"
  | "scenario"
  | "detail";

export type ElementAction = "click" | "enter" | "space" | "tab" | "type" | "scroll";

export interface Position {
  x: number;
  y: number;
}

export interface ElementStyle {
  fg?: string;
  bg?: string;
  bold: boolean;
  underline: boolean;
  inverse: boolean;
}

export interface TuiElement {
  type:
    | "container"
    | "text"
    | "list"
    | "table"
    | "input"
    | "button"
    | "progress"
    | "checkbox"
    | "radio"
    | "scrollbar"
    | "status"
    | "heading";
  role: SemanticRole | string;
  bounds: Rect;
  content?: string;
  label?: string;
  interactable: boolean;
  focused: boolean;
  cursorPosition?: Position;
  actions: ElementAction[];
  id: string;
  ref?: string;
  states: string[];
  style: ElementStyle;
  children: TuiElement[];
}

export interface ElementMeta {
  role: SemanticRole | string;
  interactable: boolean;
  focused: boolean;
  states: string[];
  bounds: Rect;
  ref: string;
  label?: string;
  content?: string;
  actions: ElementAction[];
}

export type CharTokenType =
  | "corner_tl"
  | "corner_tr"
  | "corner_bl"
  | "corner_br"
  | "edge_h"
  | "edge_v"
  | "tee_l"
  | "tee_r"
  | "tee_d"
  | "tee_u"
  | "cross"
  | "block_full"
  | "shade_dark"
  | "shade_med"
  | "shade_light"
  | "bullet"
  | "radio_on"
  | "radio_off"
  | "checkbox_on"
  | "checkbox_off"
  | "expand_collapsed"
  | "expand_expanded"
  | "scroll_up"
  | "scroll_down"
  | "scroll_thumb"
  | "text"
  | "whitespace";

export interface CharToken {
  type: CharTokenType;
  char: string;
  cp: number;
  weight: "light" | "heavy" | "double";
  style: ElementStyle;
}
