import * as vscode from "vscode";

export interface ObjJMethod {
  selector: string;
  isClassMethod: boolean;
  returnType: string;
  params: { label: string; type: string; name: string }[];
  range: vscode.Range;
  selectorRange: vscode.Range;
}

export interface ObjJIvar {
  name: string;
  type: string;
  isOutlet: boolean;
  range: vscode.Range;
  nameRange: vscode.Range;
}

export interface ObjJClass {
  name: string;
  superclass?: string;
  protocols: string[];
  category?: string;
  range: vscode.Range;
  nameRange: vscode.Range;
  ivars: ObjJIvar[];
  methods: ObjJMethod[];
}

export interface ObjJProtocol {
  name: string;
  parentProtocols: string[];
  range: vscode.Range;
  nameRange: vscode.Range;
  methods: ObjJMethod[];
}

export interface ObjJImport {
  path: string;
  isFramework: boolean;
  range: vscode.Range;
}

export interface ObjJForwardDecl {
  kind: "class" | "global" | "typedef";
  name: string;
  range: vscode.Range;
  nameRange: vscode.Range;
}

export interface ObjJParseResult {
  classes: ObjJClass[];
  protocols: ObjJProtocol[];
  imports: ObjJImport[];
  forwardDecls: ObjJForwardDecl[];
}

const RE_IMPLEMENTATION =
  /^@implementation\s+([a-zA-Z_]\w*)(?:\s*:\s*([a-zA-Z_]\w*))?(?:\s*<([^>]+)>)?(?:\s*\(([^)]+)\))?/;
const RE_PROTOCOL =
  /^@protocol\s+([a-zA-Z_]\w*)(?:\s*<([^>]+)>)?/;
const RE_END = /^@end\b/;
const RE_METHOD_START = /^([+-])\s*\(([^)]*)\)\s*(.*)/;
const RE_IMPORT =
  /^@import\s+(?:<([^>]+)>|"([^"]+)")/;
const RE_CLASS_DECL = /^@class\s+([a-zA-Z_]\w*)/;
const RE_GLOBAL_DECL = /^@global\s+([a-zA-Z_]\w*)/;
const RE_TYPEDEF_DECL = /^@typedef\s+([a-zA-Z_]\w*)/;

/**
 * Parse a selector signature string like "doThing:(CPString)arg1 withOther:(int)arg2"
 * into its selector name and parameter list.
 */
function parseMethodSignature(
  signatureStr: string
): { selector: string; params: { label: string; type: string; name: string }[] } {
  const params: { label: string; type: string; name: string }[] = [];

  // Match all label:(Type)name segments
  const paramRegex = /([a-zA-Z_]\w*)\s*:\s*\(([^)]*)\)\s*([a-zA-Z_]\w*)/g;
  let match: RegExpExecArray | null;
  const selectorParts: string[] = [];
  let foundParams = false;

  while ((match = paramRegex.exec(signatureStr)) !== null) {
    foundParams = true;
    selectorParts.push(match[1] + ":");
    params.push({
      label: match[1],
      type: match[2].trim(),
      name: match[3],
    });
  }

  if (foundParams) {
    return { selector: selectorParts.join(""), params };
  }

  // No params — simple method name
  const simpleMatch = signatureStr.match(/^([a-zA-Z_]\w*)/);
  const selector = simpleMatch ? simpleMatch[1] : signatureStr.trim();
  return { selector, params: [] };
}

/**
 * Parse a full Objective-J document and extract all structural symbols.
 */
export function parseDocument(document: vscode.TextDocument): ObjJParseResult {
  const text = document.getText();
  const lines = text.split("\n");
  const classes: ObjJClass[] = [];
  const protocols: ObjJProtocol[] = [];
  const imports: ObjJImport[] = [];
  const forwardDecls: ObjJForwardDecl[] = [];

  let currentClass: ObjJClass | null = null;
  let currentProtocol: ObjJProtocol | null = null;
  let inIvarBlock = false;
  let braceDepth = 0;
  let ivarBraceStart = -1;
  // Track if we're between @implementation and its first {
  let waitingForIvarBrace = false;

  // For multi-line method signature accumulation
  let methodAccum: {
    startLine: number;
    prefix: string;
    returnType: string;
    signatureLines: string[];
  } | null = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Skip empty lines and comments (basic)
    if (trimmed === "" || trimmed.startsWith("//")) continue;

    // --- Imports ---
    const importMatch = trimmed.match(RE_IMPORT);
    if (importMatch) {
      const importPath = importMatch[1] || importMatch[2];
      imports.push({
        path: importPath,
        isFramework: !!importMatch[1],
        range: new vscode.Range(i, 0, i, line.length),
      });
      continue;
    }

    // --- Forward declarations ---
    const classMatch = trimmed.match(RE_CLASS_DECL);
    if (classMatch && !currentClass && !currentProtocol) {
      const nameStart = line.indexOf(classMatch[1]);
      forwardDecls.push({
        kind: "class",
        name: classMatch[1],
        range: new vscode.Range(i, 0, i, line.length),
        nameRange: new vscode.Range(i, nameStart, i, nameStart + classMatch[1].length),
      });
      continue;
    }

    const globalMatch = trimmed.match(RE_GLOBAL_DECL);
    if (globalMatch) {
      const nameStart = line.indexOf(globalMatch[1]);
      forwardDecls.push({
        kind: "global",
        name: globalMatch[1],
        range: new vscode.Range(i, 0, i, line.length),
        nameRange: new vscode.Range(i, nameStart, i, nameStart + globalMatch[1].length),
      });
      continue;
    }

    const typedefMatch = trimmed.match(RE_TYPEDEF_DECL);
    if (typedefMatch) {
      const nameStart = line.indexOf(typedefMatch[1]);
      forwardDecls.push({
        kind: "typedef",
        name: typedefMatch[1],
        range: new vscode.Range(i, 0, i, line.length),
        nameRange: new vscode.Range(i, nameStart, i, nameStart + typedefMatch[1].length),
      });
      continue;
    }

    // --- @implementation ---
    const implMatch = trimmed.match(RE_IMPLEMENTATION);
    if (implMatch) {
      const nameStart = line.indexOf(implMatch[1], line.indexOf("@implementation") + 15);
      currentClass = {
        name: implMatch[1],
        superclass: implMatch[2] || undefined,
        protocols: implMatch[3] ? implMatch[3].split(",").map((s) => s.trim()) : [],
        category: implMatch[4] || undefined,
        range: new vscode.Range(i, 0, i, line.length), // end updated at @end
        nameRange: new vscode.Range(i, nameStart, i, nameStart + implMatch[1].length),
        ivars: [],
        methods: [],
      };
      waitingForIvarBrace = true;
      braceDepth = 0;

      // Check if the opening brace is on same line
      if (trimmed.includes("{")) {
        inIvarBlock = true;
        waitingForIvarBrace = false;
        ivarBraceStart = i;
        braceDepth = 1;
      }
      continue;
    }

    // --- @protocol ---
    const protoMatch = trimmed.match(RE_PROTOCOL);
    if (protoMatch) {
      const nameStart = line.indexOf(protoMatch[1], line.indexOf("@protocol") + 9);
      currentProtocol = {
        name: protoMatch[1],
        parentProtocols: protoMatch[2] ? protoMatch[2].split(",").map((s) => s.trim()) : [],
        range: new vscode.Range(i, 0, i, line.length),
        nameRange: new vscode.Range(i, nameStart, i, nameStart + protoMatch[1].length),
        methods: [],
      };
      continue;
    }

    // --- @end ---
    if (RE_END.test(trimmed)) {
      if (currentClass) {
        currentClass.range = new vscode.Range(
          currentClass.range.start.line,
          0,
          i,
          line.length
        );
        classes.push(currentClass);
        currentClass = null;
        inIvarBlock = false;
        waitingForIvarBrace = false;
        braceDepth = 0;
      }
      if (currentProtocol) {
        currentProtocol.range = new vscode.Range(
          currentProtocol.range.start.line,
          0,
          i,
          line.length
        );
        protocols.push(currentProtocol);
        currentProtocol = null;
      }
      continue;
    }

    // --- Ivar block detection ---
    if (currentClass && waitingForIvarBrace && trimmed === "{") {
      inIvarBlock = true;
      waitingForIvarBrace = false;
      ivarBraceStart = i;
      braceDepth = 1;
      continue;
    }

    if (inIvarBlock && currentClass) {
      // Count braces
      for (const ch of trimmed) {
        if (ch === "{") braceDepth++;
        if (ch === "}") braceDepth--;
      }

      if (braceDepth <= 0) {
        inIvarBlock = false;
        waitingForIvarBrace = false;
        continue;
      }

      // Parse ivar: optional @outlet, Type name (optional @accessors...);
      const ivarRegex =
        /(@outlet\s+)?([A-Z]\w*|id|BOOL|SEL|int|unsigned|float|double|char|void|long|short|signed)\s+([_a-zA-Z]\w*)/;
      const ivarMatch = trimmed.match(ivarRegex);
      if (ivarMatch) {
        const nameIdx = line.indexOf(ivarMatch[3], line.indexOf(ivarMatch[2]));
        currentClass.ivars.push({
          name: ivarMatch[3],
          type: ivarMatch[2],
          isOutlet: !!ivarMatch[1],
          range: new vscode.Range(i, 0, i, line.length),
          nameRange: new vscode.Range(i, nameIdx, i, nameIdx + ivarMatch[3].length),
        });
      }
      continue;
    }

    // After ivar block, stop waiting
    if (currentClass && waitingForIvarBrace && RE_METHOD_START.test(trimmed)) {
      waitingForIvarBrace = false;
      // Fall through to method parsing
    }

    // --- Method definitions/declarations ---
    const container = currentClass || currentProtocol;
    if (container) {
      // Handle multi-line method signatures: accumulate until we see { or ;
      if (methodAccum) {
        methodAccum.signatureLines.push(trimmed);
        if (trimmed.includes("{") || trimmed.endsWith(";")) {
          // Finish accumulating
          const fullSig = methodAccum.signatureLines.join(" ").replace(/\s*[{;]\s*$/, "");
          const { selector, params } = parseMethodSignature(fullSig);
          const selectorStart = lines[methodAccum.startLine].indexOf(
            selector.split(":")[0],
            lines[methodAccum.startLine].indexOf(")") + 1
          );
          const method: ObjJMethod = {
            selector,
            isClassMethod: methodAccum.prefix === "+",
            returnType: methodAccum.returnType,
            params,
            range: new vscode.Range(methodAccum.startLine, 0, i, line.length),
            selectorRange: new vscode.Range(
              methodAccum.startLine,
              Math.max(0, selectorStart),
              methodAccum.startLine,
              Math.max(0, selectorStart) + selector.split(":")[0].length
            ),
          };
          container.methods.push(method);
          methodAccum = null;
        }
        continue;
      }

      const methodMatch = trimmed.match(RE_METHOD_START);
      if (methodMatch) {
        const prefix = methodMatch[1]; // + or -
        const returnType = methodMatch[2].trim();
        const rest = methodMatch[3].trim();

        // Check if the full signature is on this line (has { or ;)
        if (rest.includes("{") || rest.endsWith(";")) {
          const sigStr = rest.replace(/\s*[{;]\s*$/, "");
          const { selector, params } = parseMethodSignature(sigStr);
          const selectorStart = line.indexOf(
            selector.split(":")[0],
            line.indexOf(")") + 1
          );
          const method: ObjJMethod = {
            selector,
            isClassMethod: prefix === "+",
            returnType,
            params,
            range: new vscode.Range(i, 0, i, line.length),
            selectorRange: new vscode.Range(
              i,
              Math.max(0, selectorStart),
              i,
              Math.max(0, selectorStart) + selector.split(":")[0].length
            ),
          };
          container.methods.push(method);
        } else {
          // Start accumulating
          methodAccum = {
            startLine: i,
            prefix,
            returnType,
            signatureLines: [rest],
          };
        }
      }
    }
  }

  // Handle unclosed class/protocol (malformed file)
  if (currentClass) {
    currentClass.range = new vscode.Range(
      currentClass.range.start.line,
      0,
      lines.length - 1,
      lines[lines.length - 1].length
    );
    classes.push(currentClass);
  }
  if (currentProtocol) {
    currentProtocol.range = new vscode.Range(
      currentProtocol.range.start.line,
      0,
      lines.length - 1,
      lines[lines.length - 1].length
    );
    protocols.push(currentProtocol);
  }

  return { classes, protocols, imports, forwardDecls };
}
