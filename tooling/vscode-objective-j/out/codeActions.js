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
exports.ObjJCodeActionProvider = void 0;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
/**
 * Code actions:
 * - "Add @import for ClassName" when a class is used but not imported
 * - "Generate method stubs for protocol" when conformance is missing methods
 */
class ObjJCodeActionProvider {
    constructor(index) {
        this.index = index;
    }
    provideCodeActions(document, range, context) {
        const actions = [];
        // Generate actions from diagnostics
        for (const diag of context.diagnostics) {
            if (diag.message.startsWith('Cannot resolve import')) {
                // No auto-fix for missing imports
                continue;
            }
            if (diag.message.includes("does not implement")) {
                const action = this.createMethodStubAction(document, diag);
                if (action)
                    actions.push(action);
            }
        }
        // Check if cursor is on a class name that's not imported
        const wordRange = document.getWordRangeAtPosition(range.start, /[A-Z]\w*/);
        if (wordRange) {
            const word = document.getText(wordRange);
            const importAction = this.createAddImportAction(document, word);
            if (importAction)
                actions.push(importAction);
        }
        return actions;
    }
    /**
     * Create an "Add @import" code action for a class name.
     */
    createAddImportAction(document, className) {
        // Check if already imported
        const file = this.index.getFile(document.uri);
        if (!file)
            return undefined;
        // Is this class defined in the workspace?
        const classDef = this.index.findClass(className);
        if (!classDef)
            return undefined;
        // Is it in the same file?
        if (classDef.uri.toString() === document.uri.toString())
            return undefined;
        // Check if already imported
        const classFileName = path.basename(classDef.uri.fsPath);
        const alreadyImported = file.result.imports.some((imp) => {
            const importFile = path.basename(imp.path);
            return importFile === classFileName;
        });
        if (alreadyImported)
            return undefined;
        // Compute relative path
        const currentDir = path.dirname(document.uri.fsPath);
        let relativePath = path.relative(currentDir, classDef.uri.fsPath);
        if (!relativePath.startsWith(".")) {
            relativePath = "./" + relativePath;
        }
        const action = new vscode.CodeAction(`Add @import "${relativePath}"`, vscode.CodeActionKind.QuickFix);
        // Find the insertion point: after the last @import, or at line 0
        let insertLine = 0;
        for (const imp of file.result.imports) {
            insertLine = Math.max(insertLine, imp.range.end.line + 1);
        }
        const edit = new vscode.WorkspaceEdit();
        edit.insert(document.uri, new vscode.Position(insertLine, 0), `@import "${relativePath}"\n`);
        action.edit = edit;
        return action;
    }
    /**
     * Create a "Generate method stubs" action for missing protocol methods.
     */
    createMethodStubAction(document, diagnostic) {
        // Parse the diagnostic message to extract selector and protocol
        const match = diagnostic.message.match(/Class '(\w+)' declares conformance to <(\w+)> but does not implement '([^']+)'/);
        if (!match)
            return undefined;
        const [, className, protoName, selector] = match;
        // Find the protocol to get the method signature
        const protoDef = this.index.findProtocol(protoName);
        if (!protoDef)
            return undefined;
        const method = protoDef.proto.methods.find((m) => m.selector === selector);
        if (!method)
            return undefined;
        // Find the class to know where to insert
        const file = this.index.getFile(document.uri);
        if (!file)
            return undefined;
        const cls = file.result.classes.find((c) => c.name === className && !c.category);
        if (!cls)
            return undefined;
        // Build the method stub
        const prefix = method.isClassMethod ? "+" : "-";
        let stub;
        if (method.params.length > 0) {
            const paramParts = method.params.map((p) => `${p.label}:(${p.type})${p.name}`);
            stub = `${prefix} (${method.returnType})${paramParts.join(" ")}\n{\n    \n}\n\n`;
        }
        else {
            stub = `${prefix} (${method.returnType})${method.selector}\n{\n    \n}\n\n`;
        }
        const action = new vscode.CodeAction(`Generate stub for '${selector}'`, vscode.CodeActionKind.QuickFix);
        action.diagnostics = [diagnostic];
        // Insert before @end
        const insertLine = cls.range.end.line;
        const edit = new vscode.WorkspaceEdit();
        edit.insert(document.uri, new vscode.Position(insertLine, 0), stub);
        action.edit = edit;
        return action;
    }
}
exports.ObjJCodeActionProvider = ObjJCodeActionProvider;
ObjJCodeActionProvider.providedCodeActionKinds = [
    vscode.CodeActionKind.QuickFix,
    vscode.CodeActionKind.Refactor,
];
//# sourceMappingURL=codeActions.js.map