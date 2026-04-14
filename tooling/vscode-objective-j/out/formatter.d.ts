import * as vscode from "vscode";
/**
 * Provides document formatting for Objective-J files.
 */
export declare class ObjJDocumentFormattingEditProvider implements vscode.DocumentFormattingEditProvider {
    provideDocumentFormattingEdits(document: vscode.TextDocument, options: vscode.FormattingOptions): vscode.TextEdit[];
}
/**
 * Provides range formatting for Objective-J files.
 * Formats the selected range using the same logic, but only emits edits
 * for the requested lines.
 */
export declare class ObjJDocumentRangeFormattingEditProvider implements vscode.DocumentRangeFormattingEditProvider {
    provideDocumentRangeFormattingEdits(document: vscode.TextDocument, range: vscode.Range, options: vscode.FormattingOptions): vscode.TextEdit[];
}
//# sourceMappingURL=formatter.d.ts.map