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
exports.ObjJCibProvider = void 0;
const vscode = __importStar(require("vscode"));
/**
 * Provides Cib/xib file awareness for Objective-J.
 *
 * Cappuccino uses .cib files (compiled Interface Builder files, JSON or plist)
 * and sometimes .xib files.  This provider does best-effort text matching to
 * detect outlet references inside those files and cross-references them against
 * @outlet declarations found by the Objective-J parser.
 */
class ObjJCibProvider {
    constructor(index) {
        this.index = index;
        this.cibFiles = new Map(); // uri.toString() -> content
        this.watchers = [];
        this.diagnosticCollection = vscode.languages.createDiagnosticCollection("objective-j-cib");
    }
    dispose() {
        this.diagnosticCollection.dispose();
        for (const w of this.watchers) {
            w.dispose();
        }
    }
    /**
     * Scan the workspace for .cib and .xib files, read their contents, and
     * set up file-system watchers for ongoing changes.
     */
    async indexCibFiles() {
        const uris = await vscode.workspace.findFiles("**/*.{cib,xib}", "**/node_modules/**");
        await Promise.all(uris.map((uri) => this.readCibFile(uri)));
    }
    /**
     * Start watching for .cib/.xib file changes.
     * Returns disposables that should be pushed into context.subscriptions.
     */
    watch() {
        const watcher = vscode.workspace.createFileSystemWatcher("**/*.{cib,xib}");
        const onChange = watcher.onDidChange((uri) => this.readCibFile(uri));
        const onCreate = watcher.onDidCreate((uri) => this.readCibFile(uri));
        const onDelete = watcher.onDidDelete((uri) => {
            this.cibFiles.delete(uri.toString());
        });
        this.watchers.push(watcher, onChange, onCreate, onDelete);
        return [watcher, onChange, onCreate, onDelete];
    }
    /**
     * Return the list of Cib/xib file paths that mention `outletName`.
     */
    getOutletConnections(className, outletName) {
        const matches = [];
        for (const [uriStr, content] of this.cibFiles) {
            // Best-effort: look for the outlet name in the cib content.
            // Cib files may reference outlets as plain strings in JSON keys,
            // plist values, or XML attributes.
            if (content.includes(outletName)) {
                const uri = vscode.Uri.parse(uriStr);
                matches.push(vscode.workspace.asRelativePath(uri));
            }
        }
        return matches;
    }
    /**
     * Build a hover string for an @outlet ivar, showing its Cib connection status.
     */
    provideOutletHover(className, ivarName) {
        const connections = this.getOutletConnections(className, ivarName);
        if (connections.length > 0) {
            const fileList = connections.map((f) => `- \`${f}\``).join("\n");
            return `**@outlet** \`${ivarName}\` — connected in:\n${fileList}`;
        }
        return `**@outlet** \`${ivarName}\` — ⚠️ not found in any Cib/xib file`;
    }
    /**
     * Run diagnostics on all Objective-J files, emitting informational hints
     * for @outlet ivars that are not referenced in any Cib/xib file.
     */
    diagnoseOutlets() {
        for (const { cls, uri } of this.index.allClasses()) {
            const outletIvars = cls.ivars.filter((ivar) => ivar.isOutlet);
            if (outletIvars.length === 0)
                continue;
            const diagnostics = [];
            for (const ivar of outletIvars) {
                const connections = this.getOutletConnections(cls.name, ivar.name);
                if (connections.length === 0) {
                    const diag = new vscode.Diagnostic(ivar.nameRange, `@outlet '${ivar.name}' (${ivar.type}) is not referenced in any Cib/xib file`, vscode.DiagnosticSeverity.Hint);
                    diag.source = "objective-j-cib";
                    diagnostics.push(diag);
                }
            }
            // Merge: only set if we have outlet diagnostics; clear old ones otherwise.
            this.diagnosticCollection.set(uri, diagnostics.length > 0 ? diagnostics : undefined);
        }
    }
    // ---------------------------------------------------------------------------
    // Private helpers
    // ---------------------------------------------------------------------------
    async readCibFile(uri) {
        try {
            const bytes = await vscode.workspace.fs.readFile(uri);
            this.cibFiles.set(uri.toString(), Buffer.from(bytes).toString("utf-8"));
        }
        catch {
            this.cibFiles.delete(uri.toString());
        }
    }
}
exports.ObjJCibProvider = ObjJCibProvider;
//# sourceMappingURL=cib.js.map