import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
/**
 * Signature help for message sends:
 * When typing [obj method: ← shows parameter info
 */
export declare class ObjJSignatureHelpProvider implements vscode.SignatureHelpProvider {
    private index;
    constructor(index: ObjJWorkspaceIndex);
    provideSignatureHelp(document: vscode.TextDocument, position: vscode.Position): vscode.SignatureHelp | undefined;
    private findCandidateMethods;
    private methodToSignature;
}
//# sourceMappingURL=signatureHelp.d.ts.map