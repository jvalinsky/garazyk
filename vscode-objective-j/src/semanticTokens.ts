import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
import { parseDocument } from "./parser";

/**
 * Semantic token types for Objective-J.
 * These provide richer highlighting on top of the TextMate grammar.
 */
export const TOKEN_TYPES = [
  "class",        // 0 - class names
  "interface",    // 1 - protocol names
  "method",       // 2 - method selectors
  "property",     // 3 - instance variables
  "variable",     // 4 - local variables
  "parameter",    // 5 - method parameters
  "keyword",      // 6 - ObjJ keywords
  "type",         // 7 - type names in signatures
  "function",     // 8 - function names
  "decorator",    // 9 - @ directives
] as const;

export const TOKEN_MODIFIERS = [
  "declaration",    // 0
  "definition",     // 1
  "readonly",       // 2
  "static",         // 3 - class methods
  "defaultLibrary", // 4 - framework types
] as const;

export const LEGEND = new vscode.SemanticTokensLegend(
  [...TOKEN_TYPES],
  [...TOKEN_MODIFIERS]
);

export class ObjJSemanticTokenProvider implements vscode.DocumentSemanticTokensProvider {
  constructor(private index: ObjJWorkspaceIndex) {}

  provideDocumentSemanticTokens(document: vscode.TextDocument): vscode.SemanticTokens {
    const builder = new vscode.SemanticTokensBuilder(LEGEND);
    const result = parseDocument(document);
    const text = document.getText();
    const lines = text.split("\n");

    // --- Class and protocol names in @implementation/@protocol headers ---
    for (const cls of result.classes) {
      // Class name
      builder.push(cls.nameRange, "class", ["declaration", "definition"]);

      // Superclass
      if (cls.superclass) {
        const line = lines[cls.range.start.line];
        const superIdx = line.indexOf(cls.superclass, line.indexOf(":") + 1);
        if (superIdx >= 0) {
          builder.push(
            new vscode.Range(
              cls.range.start.line, superIdx,
              cls.range.start.line, superIdx + cls.superclass.length
            ),
            "class",
            []
          );
        }
      }

      // Instance variables
      for (const ivar of cls.ivars) {
        builder.push(ivar.nameRange, "property", ["declaration"]);

        // Type of ivar
        const ivarLine = lines[ivar.range.start.line];
        const typeMatch = ivarLine.match(
          /(?:@outlet\s+)?([A-Z]\w*|id|BOOL|SEL|int|unsigned|float|double|char|void|long|short|signed)\s+/
        );
        if (typeMatch) {
          const typeIdx = ivarLine.indexOf(typeMatch[1]);
          if (typeIdx >= 0 && /^[A-Z]/.test(typeMatch[1])) {
            builder.push(
              new vscode.Range(
                ivar.range.start.line, typeIdx,
                ivar.range.start.line, typeIdx + typeMatch[1].length
              ),
              "type",
              this.isFrameworkType(typeMatch[1]) ? ["defaultLibrary"] : []
            );
          }
        }
      }

      // Methods
      for (const method of cls.methods) {
        builder.push(method.selectorRange, "method", [
          "definition",
          ...(method.isClassMethod ? ["static" as const] : []),
        ]);

        // Parameters
        for (const param of method.params) {
          // Find param name on the method's start line or range
          for (let li = method.range.start.line; li <= method.range.end.line && li < lines.length; li++) {
            const paramIdx = lines[li].indexOf(param.name);
            if (paramIdx >= 0) {
              // Verify it's actually the parameter (follows a closing paren)
              const before = lines[li].substring(0, paramIdx).trimEnd();
              if (before.endsWith(")")) {
                builder.push(
                  new vscode.Range(li, paramIdx, li, paramIdx + param.name.length),
                  "parameter",
                  ["declaration"]
                );
                break;
              }
            }
          }
        }
      }
    }

    // --- Protocol names ---
    for (const proto of result.protocols) {
      builder.push(proto.nameRange, "interface", ["declaration", "definition"]);

      for (const method of proto.methods) {
        builder.push(method.selectorRange, "method", [
          "declaration",
          ...(method.isClassMethod ? ["static" as const] : []),
        ]);
      }
    }

    // --- @directives throughout the file ---
    const directiveRegex = /@(implementation|end|protocol|import|class|global|typedef|selector|accessors|outlet|action|try|catch|finally|throw|ref|deref|required|optional|each)\b/g;
    let directiveMatch: RegExpExecArray | null;
    while ((directiveMatch = directiveRegex.exec(text)) !== null) {
      const pos = document.positionAt(directiveMatch.index);
      const endPos = document.positionAt(directiveMatch.index + directiveMatch[0].length);
      builder.push(new vscode.Range(pos, endPos), "decorator", []);
    }

    // --- self / super / _cmd ---
    const langVarRegex = /\b(self|super|_cmd)\b/g;
    let langMatch: RegExpExecArray | null;
    while ((langMatch = langVarRegex.exec(text)) !== null) {
      const pos = document.positionAt(langMatch.index);
      const endPos = document.positionAt(langMatch.index + langMatch[0].length);
      builder.push(new vscode.Range(pos, endPos), "variable", ["readonly"]);
    }

    // --- Framework type references (CP*/CG* in type positions) ---
    const typeRefRegex = /\b(CP[A-Z]\w*|CG[A-Z]\w*)\b/g;
    let typeMatch: RegExpExecArray | null;
    while ((typeMatch = typeRefRegex.exec(text)) !== null) {
      const pos = document.positionAt(typeMatch.index);
      const line = document.lineAt(pos.line).text;
      // Only mark as type if it looks like it's in a type context (after ( or as an ivar type)
      const charBefore = typeMatch.index > 0 ? text[typeMatch.index - 1] : "";
      if (charBefore === "(" || /^\s/.test(charBefore) || charBefore === "<") {
        const endPos = document.positionAt(typeMatch.index + typeMatch[0].length);
        builder.push(new vscode.Range(pos, endPos), "type", ["defaultLibrary"]);
      }
    }

    return builder.build();
  }

  private isFrameworkType(name: string): boolean {
    return /^(CP|CG)[A-Z]/.test(name);
  }
}
