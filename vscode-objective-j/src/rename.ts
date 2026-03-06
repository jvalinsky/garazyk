import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";

/**
 * Rename provider:
 * - Rename class name across all files (updates @implementation, @class, @import refs, message sends)
 * - Rename selector across all message sends, @selector() refs, and method definitions
 */
export class ObjJRenameProvider implements vscode.RenameProvider {
  constructor(private index: ObjJWorkspaceIndex) {}

  prepareRename(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.Range | { range: vscode.Range; placeholder: string } | undefined {
    const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
    if (!wordRange) return undefined;

    const word = document.getText(wordRange);

    // Can rename class names
    if (/^[A-Z]/.test(word)) {
      const cls = this.index.findClass(word);
      const proto = this.index.findProtocol(word);
      if (cls || proto) {
        return { range: wordRange, placeholder: word };
      }
    }

    // Can rename selectors (if on a selector part)
    const line = document.lineAt(position.line).text;
    const selectorInSelector = this.extractSelectorAtPosition(line, position.character);
    if (selectorInSelector) {
      return { range: wordRange, placeholder: word };
    }

    return undefined;
  }

  async provideRenameEdits(
    document: vscode.TextDocument,
    position: vscode.Position,
    newName: string
  ): Promise<vscode.WorkspaceEdit | undefined> {
    const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
    if (!wordRange) return undefined;

    const word = document.getText(wordRange);
    const edit = new vscode.WorkspaceEdit();

    // Rename class/protocol
    if (/^[A-Z]/.test(word)) {
      const cls = this.index.findClass(word);
      const proto = this.index.findProtocol(word);
      if (cls || proto) {
        await this.renameIdentifierAcrossWorkspace(word, newName, edit);
        return edit;
      }
    }

    // Rename selector
    const line = document.lineAt(position.line).text;
    const fullSelector = this.extractSelectorContext(line, position.character);
    if (fullSelector) {
      // For simple selectors (no colons), rename the word everywhere as a selector
      if (!fullSelector.includes(":")) {
        await this.renameSelectorAcrossWorkspace(fullSelector, newName, edit);
        return edit;
      }
      // For multi-part selectors, we rename just the label part the cursor is on
      // and update it in all matching full selectors
      await this.renameSelectorPartAcrossWorkspace(word, newName, fullSelector, edit);
      return edit;
    }

    return undefined;
  }

  /**
   * Rename all occurrences of an identifier (class/protocol name) across workspace.
   */
  private async renameIdentifierAcrossWorkspace(
    oldName: string,
    newName: string,
    edit: vscode.WorkspaceEdit
  ): Promise<void> {
    const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
    const regex = new RegExp(`\\b${escapeRegex(oldName)}\\b`, "g");

    for (const uri of uris) {
      try {
        const doc = await vscode.workspace.openTextDocument(uri);
        const text = doc.getText();
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
          const pos = doc.positionAt(match.index);
          const range = new vscode.Range(pos, doc.positionAt(match.index + oldName.length));
          edit.replace(uri, range, newName);
        }
      } catch {
        // skip
      }
    }
  }

  /**
   * Rename a simple (no-arg) selector across the workspace.
   */
  private async renameSelectorAcrossWorkspace(
    oldSelector: string,
    newSelector: string,
    edit: vscode.WorkspaceEdit
  ): Promise<void> {
    await this.renameIdentifierAcrossWorkspace(oldSelector, newSelector, edit);
  }

  /**
   * Rename a single label part of a multi-part selector across the workspace.
   * E.g., renaming "withOther" in "doThing:withOther:" to "andExtra" → "doThing:andExtra:"
   */
  private async renameSelectorPartAcrossWorkspace(
    oldLabel: string,
    newLabel: string,
    _fullSelector: string,
    edit: vscode.WorkspaceEdit
  ): Promise<void> {
    // Find all occurrences of oldLabel: (the label followed by colon)
    const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
    const regex = new RegExp(`\\b${escapeRegex(oldLabel)}\\s*:`, "g");

    for (const uri of uris) {
      try {
        const doc = await vscode.workspace.openTextDocument(uri);
        const text = doc.getText();
        let match: RegExpExecArray | null;

        while ((match = regex.exec(text)) !== null) {
          const pos = doc.positionAt(match.index);
          const range = new vscode.Range(pos, doc.positionAt(match.index + oldLabel.length));
          edit.replace(uri, range, newLabel);
        }
      } catch {
        // skip
      }
    }
  }

  private extractSelectorAtPosition(line: string, charPos: number): string | undefined {
    const regex = /@selector\(([^)]+)\)/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(line)) !== null) {
      if (charPos >= match.index && charPos <= match.index + match[0].length) {
        return match[1].replace(/\s/g, "");
      }
    }
    return undefined;
  }

  private extractSelectorContext(line: string, charPos: number): string | undefined {
    // Check if in @selector(...)
    const selLit = this.extractSelectorAtPosition(line, charPos);
    if (selLit) return selLit;

    // Check if on a method definition line
    const methodMatch = line.match(/^[+-]\s*\([^)]*\)\s*(.*)/);
    if (methodMatch) {
      const sigStr = methodMatch[1];
      const paramRegex = /([a-zA-Z_]\w*)\s*:/g;
      const parts: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = paramRegex.exec(sigStr)) !== null) {
        parts.push(m[1] + ":");
      }
      if (parts.length > 0) return parts.join("");
      const simpleMatch = sigStr.match(/^([a-zA-Z_]\w*)/);
      if (simpleMatch) return simpleMatch[1];
    }

    // Check if in a message send
    const labelRegex = /\b([a-zA-Z_]\w*)\s*:/g;
    const parts: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = labelRegex.exec(line)) !== null) {
      parts.push(match[1] + ":");
    }
    if (parts.length > 0) return parts.join("");

    return undefined;
  }
}

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
