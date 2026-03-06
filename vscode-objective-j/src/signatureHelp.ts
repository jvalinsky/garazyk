import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";
import { ObjJMethod } from "./parser";

/**
 * Signature help for message sends:
 * When typing [obj method: ← shows parameter info
 */
export class ObjJSignatureHelpProvider implements vscode.SignatureHelpProvider {
  constructor(private index: ObjJWorkspaceIndex) {}

  provideSignatureHelp(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.SignatureHelp | undefined {
    const line = document.lineAt(position.line).text;
    const textBefore = line.substring(0, position.character);

    // Are we inside a message send?
    let depth = 0;
    for (const ch of textBefore) {
      if (ch === "[") depth++;
      if (ch === "]") depth--;
    }
    if (depth <= 0) return undefined;

    // Extract selector parts typed so far
    const labelRegex = /\b([a-zA-Z_]\w*)\s*:/g;
    const parts: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = labelRegex.exec(textBefore)) !== null) {
      parts.push(match[1] + ":");
    }

    if (parts.length === 0) return undefined;

    const partialSelector = parts.join("");

    // Find matching methods
    const candidates = this.findCandidateMethods(partialSelector);
    if (candidates.length === 0) return undefined;

    const help = new vscode.SignatureHelp();
    help.signatures = candidates.map((c) => this.methodToSignature(c.method, c.containerName));
    help.activeSignature = 0;
    help.activeParameter = parts.length - 1;

    return help;
  }

  private findCandidateMethods(
    partialSelector: string
  ): { method: ObjJMethod; containerName: string }[] {
    const results: { method: ObjJMethod; containerName: string }[] = [];
    const seen = new Set<string>();

    for (const { cls } of this.index.allClasses()) {
      for (const method of cls.methods) {
        if (method.selector.startsWith(partialSelector) && !seen.has(method.selector)) {
          seen.add(method.selector);
          const name = cls.category ? `${cls.name}(${cls.category})` : cls.name;
          results.push({ method, containerName: name });
        }
      }
    }
    for (const { proto } of this.index.allProtocols()) {
      for (const method of proto.methods) {
        if (method.selector.startsWith(partialSelector) && !seen.has(method.selector)) {
          seen.add(method.selector);
          results.push({ method, containerName: proto.name });
        }
      }
    }

    return results;
  }

  private methodToSignature(
    method: ObjJMethod,
    containerName: string
  ): vscode.SignatureInformation {
    const prefix = method.isClassMethod ? "+" : "-";
    let label: string;
    const params: vscode.ParameterInformation[] = [];

    if (method.params.length > 0) {
      const parts: string[] = [];
      for (const p of method.params) {
        const paramStr = `${p.label}:(${p.type})${p.name}`;
        const startIdx = parts.join(" ").length + (parts.length > 0 ? 1 : 0);
        parts.push(paramStr);
        params.push(
          new vscode.ParameterInformation(
            [startIdx, startIdx + paramStr.length],
            `(${p.type}) ${p.name}`
          )
        );
      }
      label = `${prefix} (${method.returnType})${parts.join(" ")}`;
    } else {
      label = `${prefix} (${method.returnType})${method.selector}`;
    }

    const sig = new vscode.SignatureInformation(label, `${containerName}`);
    sig.parameters = params;
    return sig;
  }
}
