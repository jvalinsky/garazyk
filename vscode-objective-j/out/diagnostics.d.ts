import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Provides diagnostics for Objective-J files:
 * - Unmatched @implementation/@end
 * - Duplicate selectors in the same class
 * - Unresolved @import paths
 * - Protocol conformance: missing @required methods
 */
export declare class ObjJDiagnosticProvider {
    private collection;
    private index;
    constructor(index: ObjJWorkspaceIndex);
    dispose(): void;
    /**
     * Run diagnostics on a single document.
     */
    diagnose(document: vscode.TextDocument): Promise<void>;
    clear(uri: vscode.Uri): void;
    /**
     * Check for unmatched @implementation/@end and @protocol/@end.
     */
    private checkBalancedBlocks;
    /**
     * Check for duplicate method selectors within the same class/category.
     */
    private checkDuplicateSelectors;
    /**
     * Check that local @import paths resolve to existing files.
     */
    private checkImports;
    /**
     * Check protocol conformance: if a class declares <Protocol>,
     * warn about missing @required methods.
     */
    private checkProtocolConformance;
    /**
     * Collect selectors from the superclass chain and categories.
     */
    private collectInheritedSelectors;
}
//# sourceMappingURL=diagnostics.d.ts.map