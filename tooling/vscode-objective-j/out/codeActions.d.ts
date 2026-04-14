import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Code actions:
 * - "Add @import for ClassName" when a class is used but not imported
 * - "Generate method stubs for protocol" when conformance is missing methods
 */
export declare class ObjJCodeActionProvider implements vscode.CodeActionProvider {
    private index;
    static readonly providedCodeActionKinds: vscode.CodeActionKind[];
    constructor(index: ObjJWorkspaceIndex);
    provideCodeActions(document: vscode.TextDocument, range: vscode.Range, context: vscode.CodeActionContext): vscode.CodeAction[];
    /**
     * Create an "Add @import" code action for a class name.
     */
    private createAddImportAction;
    /**
     * Create a "Generate method stubs" action for missing protocol methods.
     */
    private createMethodStubAction;
}
//# sourceMappingURL=codeActions.d.ts.map