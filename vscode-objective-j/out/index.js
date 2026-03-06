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
exports.ObjJWorkspaceIndex = void 0;
const vscode = __importStar(require("vscode"));
const parser_1 = require("./parser");
/**
 * Workspace-wide index of all Objective-J symbols.
 * Re-parses files on change and provides lookup methods.
 */
class ObjJWorkspaceIndex {
    constructor() {
        this.files = new Map();
        this._onDidUpdate = new vscode.EventEmitter();
        this.onDidUpdate = this._onDidUpdate.event;
    }
    /**
     * Index all .j files in the workspace.
     */
    async indexWorkspace() {
        const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
        await Promise.all(uris.map((uri) => this.indexFile(uri)));
        this._onDidUpdate.fire();
    }
    /**
     * Index or re-index a single file.
     */
    async indexFile(uri) {
        try {
            const doc = await vscode.workspace.openTextDocument(uri);
            const result = (0, parser_1.parseDocument)(doc);
            this.files.set(uri.toString(), { uri, result });
        }
        catch {
            // File may have been deleted or unreadable
            this.files.delete(uri.toString());
        }
    }
    /**
     * Index from an already-open document (avoids re-reading disk).
     */
    indexDocument(doc) {
        const result = (0, parser_1.parseDocument)(doc);
        this.files.set(doc.uri.toString(), { uri: doc.uri, result });
        this._onDidUpdate.fire();
        return result;
    }
    /**
     * Remove a file from the index.
     */
    removeFile(uri) {
        this.files.delete(uri.toString());
        this._onDidUpdate.fire();
    }
    /**
     * Get parse result for a specific file.
     */
    getFile(uri) {
        return this.files.get(uri.toString());
    }
    /**
     * Find all classes across the workspace.
     */
    allClasses() {
        const result = [];
        for (const file of this.files.values()) {
            for (const cls of file.result.classes) {
                result.push({ cls, uri: file.uri });
            }
        }
        return result;
    }
    /**
     * Find all protocols across the workspace.
     */
    allProtocols() {
        const result = [];
        for (const file of this.files.values()) {
            for (const proto of file.result.protocols) {
                result.push({ proto, uri: file.uri });
            }
        }
        return result;
    }
    /**
     * Find all forward declarations.
     */
    allForwardDecls() {
        const result = [];
        for (const file of this.files.values()) {
            for (const decl of file.result.forwardDecls) {
                result.push({ decl, uri: file.uri });
            }
        }
        return result;
    }
    /**
     * Find a class definition by name (returns the @implementation, not @class forward).
     */
    findClass(name) {
        for (const file of this.files.values()) {
            for (const cls of file.result.classes) {
                if (cls.name === name && !cls.category) {
                    return { cls, uri: file.uri };
                }
            }
        }
        return undefined;
    }
    /**
     * Find all categories for a class.
     */
    findCategories(className) {
        const result = [];
        for (const file of this.files.values()) {
            for (const cls of file.result.classes) {
                if (cls.name === className && cls.category) {
                    result.push({ cls, uri: file.uri });
                }
            }
        }
        return result;
    }
    /**
     * Find a protocol definition by name.
     */
    findProtocol(name) {
        for (const file of this.files.values()) {
            for (const proto of file.result.protocols) {
                if (proto.name === name) {
                    return { proto, uri: file.uri };
                }
            }
        }
        return undefined;
    }
    /**
     * Find all methods matching a selector across the workspace.
     */
    findMethodsBySelector(selector) {
        const result = [];
        for (const file of this.files.values()) {
            for (const cls of file.result.classes) {
                for (const method of cls.methods) {
                    if (method.selector === selector) {
                        const name = cls.category ? `${cls.name}(${cls.category})` : cls.name;
                        result.push({ method, containerName: name, uri: file.uri });
                    }
                }
            }
            for (const proto of file.result.protocols) {
                for (const method of proto.methods) {
                    if (method.selector === selector) {
                        result.push({ method, containerName: proto.name, uri: file.uri });
                    }
                }
            }
        }
        return result;
    }
    /**
     * Walk the superclass chain for a class, returning all ancestor class names.
     * Stops at unknown classes or cycles.
     */
    getSuperclassChain(className, maxDepth = 20) {
        const chain = [];
        const visited = new Set();
        let current = className;
        for (let i = 0; i < maxDepth; i++) {
            const cls = this.findClass(current);
            if (!cls || !cls.cls.superclass)
                break;
            const superName = cls.cls.superclass;
            if (visited.has(superName))
                break; // cycle guard
            visited.add(superName);
            chain.push(superName);
            current = superName;
        }
        return chain;
    }
    /**
     * Get all methods available on a class, including inherited and category methods.
     */
    getAllMethodsForClass(className) {
        const results = [];
        const seenSelectors = new Set();
        // Own methods
        const cls = this.findClass(className);
        if (cls) {
            for (const m of cls.cls.methods) {
                if (!seenSelectors.has(m.selector)) {
                    seenSelectors.add(m.selector);
                    results.push({ method: m, source: className });
                }
            }
        }
        // Category methods
        const categories = this.findCategories(className);
        for (const { cls: cat } of categories) {
            for (const m of cat.methods) {
                if (!seenSelectors.has(m.selector)) {
                    seenSelectors.add(m.selector);
                    results.push({ method: m, source: `${className}(${cat.category})` });
                }
            }
        }
        // Superclass chain
        const chain = this.getSuperclassChain(className);
        for (const superName of chain) {
            const superCls = this.findClass(superName);
            if (superCls) {
                for (const m of superCls.cls.methods) {
                    if (!seenSelectors.has(m.selector)) {
                        seenSelectors.add(m.selector);
                        results.push({ method: m, source: superName });
                    }
                }
            }
            const superCats = this.findCategories(superName);
            for (const { cls: cat } of superCats) {
                for (const m of cat.methods) {
                    if (!seenSelectors.has(m.selector)) {
                        seenSelectors.add(m.selector);
                        results.push({ method: m, source: `${superName}(${cat.category})` });
                    }
                }
            }
        }
        return results;
    }
    /**
     * Get all indexed file URIs.
     */
    allFileUris() {
        return Array.from(this.files.values()).map((f) => f.uri);
    }
    /**
     * Search all symbols by a query string (for workspace symbol search).
     */
    searchSymbols(query) {
        const results = [];
        const lowerQuery = query.toLowerCase();
        for (const file of this.files.values()) {
            for (const cls of file.result.classes) {
                const displayName = cls.category ? `${cls.name} (${cls.category})` : cls.name;
                if (displayName.toLowerCase().includes(lowerQuery)) {
                    results.push(new vscode.SymbolInformation(displayName, vscode.SymbolKind.Class, cls.superclass || "", new vscode.Location(file.uri, cls.nameRange)));
                }
                for (const method of cls.methods) {
                    if (method.selector.toLowerCase().includes(lowerQuery)) {
                        results.push(new vscode.SymbolInformation(`${method.isClassMethod ? "+" : "-"} ${method.selector}`, vscode.SymbolKind.Method, displayName, new vscode.Location(file.uri, method.selectorRange)));
                    }
                }
            }
            for (const proto of file.result.protocols) {
                if (proto.name.toLowerCase().includes(lowerQuery)) {
                    results.push(new vscode.SymbolInformation(proto.name, vscode.SymbolKind.Interface, "", new vscode.Location(file.uri, proto.nameRange)));
                }
                for (const method of proto.methods) {
                    if (method.selector.toLowerCase().includes(lowerQuery)) {
                        results.push(new vscode.SymbolInformation(`${method.isClassMethod ? "+" : "-"} ${method.selector}`, vscode.SymbolKind.Method, proto.name, new vscode.Location(file.uri, method.selectorRange)));
                    }
                }
            }
            for (const decl of file.result.forwardDecls) {
                if (decl.name.toLowerCase().includes(lowerQuery)) {
                    const kind = decl.kind === "class"
                        ? vscode.SymbolKind.Class
                        : decl.kind === "typedef"
                            ? vscode.SymbolKind.TypeParameter
                            : vscode.SymbolKind.Variable;
                    results.push(new vscode.SymbolInformation(decl.name, kind, `@${decl.kind}`, new vscode.Location(file.uri, decl.nameRange)));
                }
            }
        }
        return results;
    }
}
exports.ObjJWorkspaceIndex = ObjJWorkspaceIndex;
//# sourceMappingURL=index.js.map