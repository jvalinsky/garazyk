import * as vscode from "vscode";
import { ObjJParseResult, ObjJClass, ObjJProtocol, ObjJForwardDecl, ObjJMethod } from "./parser";
export interface IndexedFile {
    uri: vscode.Uri;
    result: ObjJParseResult;
}
/**
 * Workspace-wide index of all Objective-J symbols.
 * Re-parses files on change and provides lookup methods.
 */
export declare class ObjJWorkspaceIndex {
    private files;
    private _onDidUpdate;
    readonly onDidUpdate: vscode.Event<void>;
    /**
     * Index all .j files in the workspace.
     */
    indexWorkspace(): Promise<void>;
    /**
     * Index or re-index a single file.
     */
    indexFile(uri: vscode.Uri): Promise<void>;
    /**
     * Index from an already-open document (avoids re-reading disk).
     */
    indexDocument(doc: vscode.TextDocument): ObjJParseResult;
    /**
     * Remove a file from the index.
     */
    removeFile(uri: vscode.Uri): void;
    /**
     * Get parse result for a specific file.
     */
    getFile(uri: vscode.Uri): IndexedFile | undefined;
    /**
     * Find all classes across the workspace.
     */
    allClasses(): {
        cls: ObjJClass;
        uri: vscode.Uri;
    }[];
    /**
     * Find all protocols across the workspace.
     */
    allProtocols(): {
        proto: ObjJProtocol;
        uri: vscode.Uri;
    }[];
    /**
     * Find all forward declarations.
     */
    allForwardDecls(): {
        decl: ObjJForwardDecl;
        uri: vscode.Uri;
    }[];
    /**
     * Find a class definition by name (returns the @implementation, not @class forward).
     */
    findClass(name: string): {
        cls: ObjJClass;
        uri: vscode.Uri;
    } | undefined;
    /**
     * Find all categories for a class.
     */
    findCategories(className: string): {
        cls: ObjJClass;
        uri: vscode.Uri;
    }[];
    /**
     * Find a protocol definition by name.
     */
    findProtocol(name: string): {
        proto: ObjJProtocol;
        uri: vscode.Uri;
    } | undefined;
    /**
     * Find all methods matching a selector across the workspace.
     */
    findMethodsBySelector(selector: string): {
        method: ObjJMethod;
        containerName: string;
        uri: vscode.Uri;
    }[];
    /**
     * Walk the superclass chain for a class, returning all ancestor class names.
     * Stops at unknown classes or cycles.
     */
    getSuperclassChain(className: string, maxDepth?: number): string[];
    /**
     * Get all methods available on a class, including inherited and category methods.
     */
    getAllMethodsForClass(className: string): {
        method: import("./parser").ObjJMethod;
        source: string;
    }[];
    /**
     * Get all indexed file URIs.
     */
    allFileUris(): vscode.Uri[];
    /**
     * Search all symbols by a query string (for workspace symbol search).
     */
    searchSymbols(query: string): vscode.SymbolInformation[];
}
//# sourceMappingURL=index.d.ts.map