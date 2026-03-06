import * as vscode from "vscode";
export interface ObjJMethod {
    selector: string;
    isClassMethod: boolean;
    returnType: string;
    params: {
        label: string;
        type: string;
        name: string;
    }[];
    range: vscode.Range;
    selectorRange: vscode.Range;
}
export interface ObjJIvar {
    name: string;
    type: string;
    isOutlet: boolean;
    range: vscode.Range;
    nameRange: vscode.Range;
}
export interface ObjJClass {
    name: string;
    superclass?: string;
    protocols: string[];
    category?: string;
    range: vscode.Range;
    nameRange: vscode.Range;
    ivars: ObjJIvar[];
    methods: ObjJMethod[];
}
export interface ObjJProtocol {
    name: string;
    parentProtocols: string[];
    range: vscode.Range;
    nameRange: vscode.Range;
    methods: ObjJMethod[];
}
export interface ObjJImport {
    path: string;
    isFramework: boolean;
    range: vscode.Range;
}
export interface ObjJForwardDecl {
    kind: "class" | "global" | "typedef";
    name: string;
    range: vscode.Range;
    nameRange: vscode.Range;
}
export interface ObjJParseResult {
    classes: ObjJClass[];
    protocols: ObjJProtocol[];
    imports: ObjJImport[];
    forwardDecls: ObjJForwardDecl[];
}
/**
 * Parse a full Objective-J document and extract all structural symbols.
 */
export declare function parseDocument(document: vscode.TextDocument): ObjJParseResult;
//# sourceMappingURL=parser.d.ts.map