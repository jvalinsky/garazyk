import * as vscode from "vscode";
/**
 * Folding range provider for Objective-J that offers structure-aware folding
 * beyond the basic brace-matching in language-configuration.json.
 */
export declare class ObjJFoldingRangeProvider implements vscode.FoldingRangeProvider {
    provideFoldingRanges(document: vscode.TextDocument): vscode.FoldingRange[];
}
//# sourceMappingURL=folding.d.ts.map