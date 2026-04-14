import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Rename provider:
 * - Rename class name across all files (updates @implementation, @class, @import refs, message sends)
 * - Rename selector across all message sends, @selector() refs, and method definitions
 */
export declare class ObjJRenameProvider implements vscode.RenameProvider {
    private index;
    constructor(index: ObjJWorkspaceIndex);
    prepareRename(document: vscode.TextDocument, position: vscode.Position): vscode.Range | {
        range: vscode.Range;
        placeholder: string;
    } | undefined;
    provideRenameEdits(document: vscode.TextDocument, position: vscode.Position, newName: string): Promise<vscode.WorkspaceEdit | undefined>;
    /**
     * Rename all occurrences of an identifier (class/protocol name) across workspace.
     */
    private renameIdentifierAcrossWorkspace;
    /**
     * Rename a simple (no-arg) selector across the workspace.
     */
    private renameSelectorAcrossWorkspace;
    /**
     * Rename a single label part of a multi-part selector across the workspace.
     * E.g., renaming "withOther" in "doThing:withOther:" to "andExtra" → "doThing:andExtra:"
     */
    private renameSelectorPartAcrossWorkspace;
    private extractSelectorAtPosition;
    private extractSelectorContext;
}
//# sourceMappingURL=rename.d.ts.map