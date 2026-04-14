import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Provides Cib/xib file awareness for Objective-J.
 *
 * Cappuccino uses .cib files (compiled Interface Builder files, JSON or plist)
 * and sometimes .xib files.  This provider does best-effort text matching to
 * detect outlet references inside those files and cross-references them against
 * @outlet declarations found by the Objective-J parser.
 */
export declare class ObjJCibProvider {
    private index;
    private cibFiles;
    private diagnosticCollection;
    private watchers;
    constructor(index: ObjJWorkspaceIndex);
    dispose(): void;
    /**
     * Scan the workspace for .cib and .xib files, read their contents, and
     * set up file-system watchers for ongoing changes.
     */
    indexCibFiles(): Promise<void>;
    /**
     * Start watching for .cib/.xib file changes.
     * Returns disposables that should be pushed into context.subscriptions.
     */
    watch(): vscode.Disposable[];
    /**
     * Return the list of Cib/xib file paths that mention `outletName`.
     */
    getOutletConnections(className: string, outletName: string): string[];
    /**
     * Build a hover string for an @outlet ivar, showing its Cib connection status.
     */
    provideOutletHover(className: string, ivarName: string): string | undefined;
    /**
     * Run diagnostics on all Objective-J files, emitting informational hints
     * for @outlet ivars that are not referenced in any Cib/xib file.
     */
    diagnoseOutlets(): void;
    private readCibFile;
}
//# sourceMappingURL=cib.d.ts.map