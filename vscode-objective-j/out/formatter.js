"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ObjJDocumentRangeFormattingEditProvider = exports.ObjJDocumentFormattingEditProvider = void 0;
const vscode = __importStar(require("vscode"));
const RE_IMPL_OR_PROTO = /^@(implementation|protocol)\b/;
const RE_END = /^@end\b/;
const RE_METHOD_START = /^[+-]\s*\(/;
const RE_BLOCK_COMMENT_START = /\/\*/;
const RE_BLOCK_COMMENT_END = /\*\//;
/**
 * Determine whether a line is a continuation of a multi-param method signature.
 * Continuation lines look like:  `  with:(int)arg2`  (a label followed by colon).
 */
function isMethodContinuationLine(trimmed) {
    return /^[a-zA-Z_]\w*\s*:\s*\(/.test(trimmed);
}
/**
 * Find the column of the first `:` in a method-start line (e.g. `- (void)doThing:(CPString)arg1`).
 * Returns -1 if no colon is found.
 */
function findFirstColonColumn(line) {
    // Skip the return-type paren group, then find the first `:`
    const afterReturnType = line.indexOf(")", line.indexOf("("));
    if (afterReturnType === -1)
        return -1;
    const colonIdx = line.indexOf(":", afterReturnType + 1);
    return colonIdx;
}
/**
 * Format an array of lines according to Objective-J conventions.
 * Returns the formatted lines as a single string.
 */
function formatLines(lines, tabSize, insertSpaces) {
    const indent = insertSpaces ? " ".repeat(tabSize) : "\t";
    const result = [];
    let inImplOrProto = false;
    let inIvarBlock = false;
    let braceDepth = 0;
    let inBlockComment = false;
    // For multi-line method signature colon alignment
    let methodColonColumn = -1;
    let inMethodSignature = false;
    for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        const trimmed = raw.trim();
        // Preserve blank lines
        if (trimmed === "") {
            result.push("");
            inMethodSignature = false;
            methodColonColumn = -1;
            continue;
        }
        // Handle block comments
        if (inBlockComment) {
            // Inside a block comment — preserve as-is (with current indent context)
            result.push(raw);
            if (RE_BLOCK_COMMENT_END.test(trimmed)) {
                inBlockComment = false;
            }
            continue;
        }
        if (RE_BLOCK_COMMENT_START.test(trimmed) && !RE_BLOCK_COMMENT_END.test(trimmed)) {
            // Block comment starts and doesn't end on this line
            // Apply current indentation then preserve rest
            const level = computeIndentLevel();
            result.push(indent.repeat(level) + trimmed);
            inBlockComment = true;
            continue;
        }
        // Single-line comments: apply current indentation, preserve content
        if (trimmed.startsWith("//")) {
            const level = computeIndentLevel();
            result.push(indent.repeat(level) + trimmed);
            continue;
        }
        // Single-line block comment (/* ... */ on same line)
        if (RE_BLOCK_COMMENT_START.test(trimmed) && RE_BLOCK_COMMENT_END.test(trimmed)) {
            const level = computeIndentLevel();
            result.push(indent.repeat(level) + trimmed);
            continue;
        }
        // @implementation / @protocol — always at column 0
        if (RE_IMPL_OR_PROTO.test(trimmed)) {
            result.push(trimmed);
            inImplOrProto = true;
            inMethodSignature = false;
            methodColonColumn = -1;
            braceDepth = 0;
            // Check if ivar brace opens on same line
            if (trimmed.includes("{")) {
                inIvarBlock = true;
                braceDepth = 1;
            }
            continue;
        }
        // @end — always at column 0
        if (RE_END.test(trimmed)) {
            result.push(trimmed);
            inImplOrProto = false;
            inIvarBlock = false;
            inMethodSignature = false;
            methodColonColumn = -1;
            braceDepth = 0;
            continue;
        }
        // Outside any @implementation/@protocol block — don't reformat
        if (!inImplOrProto) {
            result.push(raw);
            continue;
        }
        // --- Inside @implementation/@protocol block ---
        // Ivar block opening brace (standalone `{` right after @implementation)
        if (!inIvarBlock && braceDepth === 0 && trimmed === "{") {
            result.push(trimmed);
            inIvarBlock = true;
            braceDepth = 1;
            continue;
        }
        // Inside ivar block
        if (inIvarBlock) {
            for (const ch of trimmed) {
                if (ch === "{")
                    braceDepth++;
                if (ch === "}")
                    braceDepth--;
            }
            if (braceDepth <= 0) {
                // Closing brace of ivar block — at column 0
                result.push(trimmed);
                inIvarBlock = false;
                braceDepth = 0;
            }
            else {
                // Ivar declarations — indent level 1
                result.push(indent + trimmed);
            }
            continue;
        }
        // Method signature start line
        if (RE_METHOD_START.test(trimmed)) {
            inMethodSignature = true;
            // Method signatures at column 0 (within the impl block)
            const formatted = trimmed;
            result.push(formatted);
            methodColonColumn = findFirstColonColumn(formatted);
            // If the line contains `{` or `;`, the signature is complete
            if (trimmed.includes("{")) {
                inMethodSignature = false;
                methodColonColumn = -1;
                braceDepth = 1;
            }
            else if (trimmed.endsWith(";")) {
                inMethodSignature = false;
                methodColonColumn = -1;
            }
            continue;
        }
        // Method signature continuation line (colon alignment)
        if (inMethodSignature && isMethodContinuationLine(trimmed)) {
            if (methodColonColumn > 0) {
                // Align the colon of this continuation line with methodColonColumn
                const colonInTrimmed = trimmed.indexOf(":");
                const padding = methodColonColumn - colonInTrimmed;
                if (padding > 0) {
                    result.push(" ".repeat(padding) + trimmed);
                }
                else {
                    result.push(trimmed);
                }
            }
            else {
                result.push(indent + trimmed);
            }
            // Check if signature ends on this line
            if (trimmed.includes("{")) {
                inMethodSignature = false;
                methodColonColumn = -1;
                braceDepth = 1;
            }
            else if (trimmed.endsWith(";")) {
                inMethodSignature = false;
                methodColonColumn = -1;
            }
            continue;
        }
        // Opening brace for method body (standalone `{` after method signature)
        if (inMethodSignature && trimmed === "{") {
            result.push(trimmed);
            inMethodSignature = false;
            methodColonColumn = -1;
            braceDepth = 1;
            continue;
        }
        // End of method signature on non-continuation line
        if (inMethodSignature) {
            inMethodSignature = false;
            methodColonColumn = -1;
        }
        // Method body — brace-based indentation
        if (braceDepth > 0) {
            // Count braces to determine indent before/after
            let closingFirst = trimmed.startsWith("}");
            let level = braceDepth;
            if (closingFirst)
                level = braceDepth - 1;
            // Update braceDepth
            for (const ch of trimmed) {
                if (ch === "{")
                    braceDepth++;
                if (ch === "}")
                    braceDepth--;
            }
            if (level < 0)
                level = 0;
            result.push(indent.repeat(level) + trimmed);
            if (braceDepth <= 0) {
                braceDepth = 0;
            }
            continue;
        }
        // Fallback: anything else inside impl at indent 0
        result.push(trimmed);
    }
    return result.join("\n");
    function computeIndentLevel() {
        if (!inImplOrProto)
            return 0;
        if (inIvarBlock)
            return 1;
        if (braceDepth > 0)
            return braceDepth;
        return 0;
    }
}
/**
 * Provides document formatting for Objective-J files.
 */
class ObjJDocumentFormattingEditProvider {
    provideDocumentFormattingEdits(document, options) {
        const text = document.getText();
        const lines = text.split("\n");
        const formatted = formatLines(lines, options.tabSize, options.insertSpaces);
        if (formatted === text)
            return [];
        const fullRange = new vscode.Range(document.positionAt(0), document.positionAt(text.length));
        return [vscode.TextEdit.replace(fullRange, formatted)];
    }
}
exports.ObjJDocumentFormattingEditProvider = ObjJDocumentFormattingEditProvider;
/**
 * Provides range formatting for Objective-J files.
 * Formats the selected range using the same logic, but only emits edits
 * for the requested lines.
 */
class ObjJDocumentRangeFormattingEditProvider {
    provideDocumentRangeFormattingEdits(document, range, options) {
        // Format the entire document to get correct context, then extract the range
        const text = document.getText();
        const lines = text.split("\n");
        const formatted = formatLines(lines, options.tabSize, options.insertSpaces);
        const formattedLines = formatted.split("\n");
        const edits = [];
        const startLine = range.start.line;
        const endLine = Math.min(range.end.line, lines.length - 1);
        for (let i = startLine; i <= endLine; i++) {
            if (i < formattedLines.length && lines[i] !== formattedLines[i]) {
                const lineRange = new vscode.Range(i, 0, i, lines[i].length);
                edits.push(vscode.TextEdit.replace(lineRange, formattedLines[i]));
            }
        }
        return edits;
    }
}
exports.ObjJDocumentRangeFormattingEditProvider = ObjJDocumentRangeFormattingEditProvider;
//# sourceMappingURL=formatter.js.map