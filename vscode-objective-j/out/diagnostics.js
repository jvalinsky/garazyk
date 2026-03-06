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
exports.ObjJDiagnosticProvider = void 0;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
/**
 * Provides diagnostics for Objective-J files:
 * - Unmatched @implementation/@end
 * - Duplicate selectors in the same class
 * - Unresolved @import paths
 * - Protocol conformance: missing @required methods
 */
class ObjJDiagnosticProvider {
    constructor(index) {
        this.collection = vscode.languages.createDiagnosticCollection("objective-j");
        this.index = index;
    }
    dispose() {
        this.collection.dispose();
    }
    /**
     * Run diagnostics on a single document.
     */
    async diagnose(document) {
        if (document.languageId !== "objective-j")
            return;
        const diagnostics = [];
        const text = document.getText();
        const lines = text.split("\n");
        this.checkBalancedBlocks(lines, diagnostics);
        const file = this.index.getFile(document.uri);
        if (file) {
            this.checkDuplicateSelectors(file.result, diagnostics);
            await this.checkImports(document, file.result, diagnostics);
            this.checkProtocolConformance(file.result, diagnostics);
        }
        this.collection.set(document.uri, diagnostics);
    }
    clear(uri) {
        this.collection.delete(uri);
    }
    /**
     * Check for unmatched @implementation/@end and @protocol/@end.
     */
    checkBalancedBlocks(lines, diagnostics) {
        const stack = [];
        for (let i = 0; i < lines.length; i++) {
            const trimmed = lines[i].trim();
            if (trimmed.startsWith("//"))
                continue;
            if (/^@implementation\b/.test(trimmed)) {
                stack.push({ keyword: "@implementation", line: i });
            }
            else if (/^@protocol\b/.test(trimmed) && !/@protocol\s*\(/.test(trimmed)) {
                stack.push({ keyword: "@protocol", line: i });
            }
            else if (/^@end\b/.test(trimmed)) {
                if (stack.length === 0) {
                    diagnostics.push(new vscode.Diagnostic(new vscode.Range(i, 0, i, trimmed.length), "Unexpected @end without matching @implementation or @protocol", vscode.DiagnosticSeverity.Error));
                }
                else {
                    stack.pop();
                }
            }
        }
        // Remaining unclosed blocks
        for (const open of stack) {
            diagnostics.push(new vscode.Diagnostic(new vscode.Range(open.line, 0, open.line, lines[open.line].length), `${open.keyword} is missing a matching @end`, vscode.DiagnosticSeverity.Error));
        }
    }
    /**
     * Check for duplicate method selectors within the same class/category.
     */
    checkDuplicateSelectors(result, diagnostics) {
        for (const cls of result.classes) {
            const seen = new Map();
            for (const method of cls.methods) {
                const key = `${method.isClassMethod ? "+" : "-"}${method.selector}`;
                const existing = seen.get(key);
                if (existing) {
                    diagnostics.push(new vscode.Diagnostic(method.selectorRange, `Duplicate method '${method.selector}' in ${cls.category ? `${cls.name}(${cls.category})` : cls.name}`, vscode.DiagnosticSeverity.Warning));
                }
                else {
                    seen.set(key, method.selectorRange);
                }
            }
        }
    }
    /**
     * Check that local @import paths resolve to existing files.
     */
    async checkImports(document, result, diagnostics) {
        for (const imp of result.imports) {
            if (imp.isFramework)
                continue; // Can't verify framework imports
            // Resolve relative to the current file
            const dir = path.dirname(document.uri.fsPath);
            const resolved = path.resolve(dir, imp.path);
            const resolvedUri = vscode.Uri.file(resolved);
            try {
                await vscode.workspace.fs.stat(resolvedUri);
            }
            catch {
                diagnostics.push(new vscode.Diagnostic(imp.range, `Cannot resolve import "${imp.path}"`, vscode.DiagnosticSeverity.Warning));
            }
        }
    }
    /**
     * Check protocol conformance: if a class declares <Protocol>,
     * warn about missing @required methods.
     */
    checkProtocolConformance(result, diagnostics) {
        for (const cls of result.classes) {
            if (cls.protocols.length === 0)
                continue;
            const classSelectors = new Set(cls.methods.map((m) => m.selector));
            // Also check superclass and category methods
            const superMethods = this.collectInheritedSelectors(cls.name);
            for (const sel of superMethods) {
                classSelectors.add(sel);
            }
            for (const protoName of cls.protocols) {
                const protoDef = this.index.findProtocol(protoName);
                if (!protoDef)
                    continue;
                for (const method of protoDef.proto.methods) {
                    // Only check @required methods (we don't track required vs optional in parser yet,
                    // so check all protocol methods — this is a best-effort approach)
                    if (!classSelectors.has(method.selector)) {
                        diagnostics.push(new vscode.Diagnostic(cls.nameRange, `Class '${cls.name}' declares conformance to <${protoName}> but does not implement '${method.selector}'`, vscode.DiagnosticSeverity.Hint));
                    }
                }
            }
        }
    }
    /**
     * Collect selectors from the superclass chain and categories.
     */
    collectInheritedSelectors(className) {
        const selectors = new Set();
        // Categories
        const categories = this.index.findCategories(className);
        for (const { cls } of categories) {
            for (const m of cls.methods) {
                selectors.add(m.selector);
            }
        }
        // Superclass chain
        const chain = this.index.getSuperclassChain(className);
        for (const superName of chain) {
            const superCls = this.index.findClass(superName);
            if (superCls) {
                for (const m of superCls.cls.methods) {
                    selectors.add(m.selector);
                }
            }
            const superCats = this.index.findCategories(superName);
            for (const { cls } of superCats) {
                for (const m of cls.methods) {
                    selectors.add(m.selector);
                }
            }
        }
        return selectors;
    }
}
exports.ObjJDiagnosticProvider = ObjJDiagnosticProvider;
//# sourceMappingURL=diagnostics.js.map