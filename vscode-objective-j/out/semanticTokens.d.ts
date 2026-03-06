import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Semantic token types for Objective-J.
 * These provide richer highlighting on top of the TextMate grammar.
 */
export declare const TOKEN_TYPES: readonly ["class", "interface", "method", "property", "variable", "parameter", "keyword", "type", "function", "decorator"];
export declare const TOKEN_MODIFIERS: readonly ["declaration", "definition", "readonly", "static", "defaultLibrary"];
export declare const LEGEND: vscode.SemanticTokensLegend;
export declare class ObjJSemanticTokenProvider implements vscode.DocumentSemanticTokensProvider {
    private index;
    constructor(index: ObjJWorkspaceIndex);
    provideDocumentSemanticTokens(document: vscode.TextDocument): vscode.SemanticTokens;
    private isFrameworkType;
}
//# sourceMappingURL=semanticTokens.d.ts.map