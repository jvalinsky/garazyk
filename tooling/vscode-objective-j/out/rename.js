"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ObjJRenameProvider = void 0;
const vscode = __importStar(require("vscode"));
/**
 * Rename provider:
 * - Rename class name across all files (updates @implementation, @class, @import refs, message sends)
 * - Rename selector across all message sends, @selector() refs, and method definitions
 */
class ObjJRenameProvider {
    constructor(index) {
        this.index = index;
    }
    prepareRename(document, position) {
        const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
        if (!wordRange)
            return undefined;
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
    async provideRenameEdits(document, position, newName) {
        const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
        if (!wordRange)
            return undefined;
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
    async renameIdentifierAcrossWorkspace(oldName, newName, edit) {
        const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
        const regex = new RegExp(`\\b${escapeRegex(oldName)}\\b`, "g");
        for (const uri of uris) {
            try {
                const doc = await vscode.workspace.openTextDocument(uri);
                const text = doc.getText();
                let match;
                while ((match = regex.exec(text)) !== null) {
                    const pos = doc.positionAt(match.index);
                    const range = new vscode.Range(pos, doc.positionAt(match.index + oldName.length));
                    edit.replace(uri, range, newName);
                }
            }
            catch {
                // skip
            }
        }
    }
    /**
     * Rename a simple (no-arg) selector across the workspace.
     */
    async renameSelectorAcrossWorkspace(oldSelector, newSelector, edit) {
        await this.renameIdentifierAcrossWorkspace(oldSelector, newSelector, edit);
    }
    /**
     * Rename a single label part of a multi-part selector across the workspace.
     * E.g., renaming "withOther" in "doThing:withOther:" to "andExtra" → "doThing:andExtra:"
     */
    async renameSelectorPartAcrossWorkspace(oldLabel, newLabel, _fullSelector, edit) {
        // Find all occurrences of oldLabel: (the label followed by colon)
        const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
        const regex = new RegExp(`\\b${escapeRegex(oldLabel)}\\s*:`, "g");
        for (const uri of uris) {
            try {
                const doc = await vscode.workspace.openTextDocument(uri);
                const text = doc.getText();
                let match;
                while ((match = regex.exec(text)) !== null) {
                    const pos = doc.positionAt(match.index);
                    const range = new vscode.Range(pos, doc.positionAt(match.index + oldLabel.length));
                    edit.replace(uri, range, newLabel);
                }
            }
            catch {
                // skip
            }
        }
    }
    extractSelectorAtPosition(line, charPos) {
        const regex = /@selector\(([^)]+)\)/g;
        let match;
        while ((match = regex.exec(line)) !== null) {
            if (charPos >= match.index && charPos <= match.index + match[0].length) {
                return match[1].replace(/\s/g, "");
            }
        }
        return undefined;
    }
    extractSelectorContext(line, charPos) {
        // Check if in @selector(...)
        const selLit = this.extractSelectorAtPosition(line, charPos);
        if (selLit)
            return selLit;
        // Check if on a method definition line
        const methodMatch = line.match(/^[+-]\s*\([^)]*\)\s*(.*)/);
        if (methodMatch) {
            const sigStr = methodMatch[1];
            const paramRegex = /([a-zA-Z_]\w*)\s*:/g;
            const parts = [];
            let m;
            while ((m = paramRegex.exec(sigStr)) !== null) {
                parts.push(m[1] + ":");
            }
            if (parts.length > 0)
                return parts.join("");
            const simpleMatch = sigStr.match(/^([a-zA-Z_]\w*)/);
            if (simpleMatch)
                return simpleMatch[1];
        }
        // Check if in a message send
        const labelRegex = /\b([a-zA-Z_]\w*)\s*:/g;
        const parts = [];
        let match;
        while ((match = labelRegex.exec(line)) !== null) {
            parts.push(match[1] + ":");
        }
        if (parts.length > 0)
            return parts.join("");
        return undefined;
    }
}
exports.ObjJRenameProvider = ObjJRenameProvider;
function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
//# sourceMappingURL=rename.js.map