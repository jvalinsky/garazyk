import * as vscode from "vscode";

const RE_IMPLEMENTATION =
  /^@implementation\s+([a-zA-Z_]\w*)(?:\s*:\s*([a-zA-Z_]\w*))?(?:\s*<([^>]+)>)?(?:\s*\(([^)]+)\))?/;
const RE_PROTOCOL = /^@protocol\s+([a-zA-Z_]\w*)(?:\s*<([^>]+)>)?/;
const RE_END = /^@end\b/;
const RE_METHOD_START = /^([+-])\s*\(([^)]*)\)\s*(.*)/;
const RE_IMPORT = /^@import\s+(?:<([^>]+)>|"([^"]+)")/;
const RE_BLOCK_COMMENT_START = /\/\*/;
const RE_BLOCK_COMMENT_END = /\*\//;

/**
 * Folding range provider for Objective-J that offers structure-aware folding
 * beyond the basic brace-matching in language-configuration.json.
 */
export class ObjJFoldingRangeProvider implements vscode.FoldingRangeProvider {
  provideFoldingRanges(document: vscode.TextDocument): vscode.FoldingRange[] {
    const lines = document.getText().split("\n");
    const ranges: vscode.FoldingRange[] = [];

    let inBlockComment = false;
    let blockCommentStart = -1;
    let importGroupStart = -1;
    let importGroupEnd = -1;

    const blockStack: { kind: "implementation" | "protocol"; line: number }[] = [];
    let ivarBraceStart = -1;
    let ivarBraceDepth = 0;
    let waitingForIvarBrace = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();

      // --- Multi-line comments ---
      if (inBlockComment) {
        if (RE_BLOCK_COMMENT_END.test(trimmed)) {
          inBlockComment = false;
          if (blockCommentStart < i) {
            ranges.push(new vscode.FoldingRange(blockCommentStart, i, vscode.FoldingRangeKind.Comment));
          }
        }
        continue;
      }

      if (RE_BLOCK_COMMENT_START.test(trimmed) && !RE_BLOCK_COMMENT_END.test(trimmed)) {
        inBlockComment = true;
        blockCommentStart = i;
        continue;
      }

      // --- Import groups ---
      if (RE_IMPORT.test(trimmed)) {
        if (importGroupStart < 0) {
          importGroupStart = i;
        }
        importGroupEnd = i;
        continue;
      } else if (importGroupStart >= 0) {
        if (importGroupEnd > importGroupStart) {
          ranges.push(new vscode.FoldingRange(importGroupStart, importGroupEnd, vscode.FoldingRangeKind.Imports));
        }
        importGroupStart = -1;
        importGroupEnd = -1;
      }

      if (trimmed === "" || trimmed.startsWith("//")) continue;

      // --- @implementation ---
      if (RE_IMPLEMENTATION.test(trimmed)) {
        blockStack.push({ kind: "implementation", line: i });
        waitingForIvarBrace = true;
        ivarBraceDepth = 0;

        if (trimmed.includes("{")) {
          waitingForIvarBrace = false;
          ivarBraceStart = i;
          ivarBraceDepth = 1;
        }
        continue;
      }

      // --- @protocol ---
      if (RE_PROTOCOL.test(trimmed)) {
        blockStack.push({ kind: "protocol", line: i });
        continue;
      }

      // --- @end ---
      if (RE_END.test(trimmed)) {
        if (blockStack.length > 0) {
          const block = blockStack.pop()!;
          if (block.line < i) {
            ranges.push(new vscode.FoldingRange(block.line, i, vscode.FoldingRangeKind.Region));
          }
        }
        continue;
      }

      // --- Ivar block detection ---
      if (waitingForIvarBrace) {
        if (trimmed === "{") {
          waitingForIvarBrace = false;
          ivarBraceStart = i;
          ivarBraceDepth = 1;
          continue;
        }
        if (RE_METHOD_START.test(trimmed)) {
          waitingForIvarBrace = false;
        }
      }

      if (ivarBraceDepth > 0) {
        for (const ch of trimmed) {
          if (ch === "{") ivarBraceDepth++;
          if (ch === "}") ivarBraceDepth--;
        }
        if (ivarBraceDepth <= 0) {
          if (ivarBraceStart < i) {
            ranges.push(new vscode.FoldingRange(ivarBraceStart, i));
          }
          ivarBraceDepth = 0;
          ivarBraceStart = -1;
        }
        continue;
      }

      // --- Method bodies ---
      if (blockStack.length > 0 && RE_METHOD_START.test(trimmed)) {
        const methodStart = i;
        let braceDepth = 0;
        let foundBody = false;

        for (let j = i; j < lines.length; j++) {
          const mLine = lines[j].trim();
          for (const ch of mLine) {
            if (ch === "{") {
              braceDepth++;
              foundBody = true;
            }
            if (ch === "}") braceDepth--;
          }
          if (foundBody && braceDepth <= 0) {
            if (methodStart < j) {
              ranges.push(new vscode.FoldingRange(methodStart, j));
            }
            i = j;
            break;
          }
        }
      }
    }

    // Flush trailing import group
    if (importGroupStart >= 0 && importGroupEnd > importGroupStart) {
      ranges.push(new vscode.FoldingRange(importGroupStart, importGroupEnd, vscode.FoldingRangeKind.Imports));
    }

    return ranges;
  }
}
