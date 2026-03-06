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
exports.ObjJSignatureHelpProvider = void 0;
const vscode = __importStar(require("vscode"));
/**
 * Signature help for message sends:
 * When typing [obj method: ← shows parameter info
 */
class ObjJSignatureHelpProvider {
    constructor(index) {
        this.index = index;
    }
    provideSignatureHelp(document, position) {
        const line = document.lineAt(position.line).text;
        const textBefore = line.substring(0, position.character);
        // Are we inside a message send?
        let depth = 0;
        for (const ch of textBefore) {
            if (ch === "[")
                depth++;
            if (ch === "]")
                depth--;
        }
        if (depth <= 0)
            return undefined;
        // Extract selector parts typed so far
        const labelRegex = /\b([a-zA-Z_]\w*)\s*:/g;
        const parts = [];
        let match;
        while ((match = labelRegex.exec(textBefore)) !== null) {
            parts.push(match[1] + ":");
        }
        if (parts.length === 0)
            return undefined;
        const partialSelector = parts.join("");
        // Find matching methods
        const candidates = this.findCandidateMethods(partialSelector);
        if (candidates.length === 0)
            return undefined;
        const help = new vscode.SignatureHelp();
        help.signatures = candidates.map((c) => this.methodToSignature(c.method, c.containerName));
        help.activeSignature = 0;
        help.activeParameter = parts.length - 1;
        return help;
    }
    findCandidateMethods(partialSelector) {
        const results = [];
        const seen = new Set();
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
    methodToSignature(method, containerName) {
        const prefix = method.isClassMethod ? "+" : "-";
        let label;
        const params = [];
        if (method.params.length > 0) {
            const parts = [];
            for (const p of method.params) {
                const paramStr = `${p.label}:(${p.type})${p.name}`;
                const startIdx = parts.join(" ").length + (parts.length > 0 ? 1 : 0);
                parts.push(paramStr);
                params.push(new vscode.ParameterInformation([startIdx, startIdx + paramStr.length], `(${p.type}) ${p.name}`));
            }
            label = `${prefix} (${method.returnType})${parts.join(" ")}`;
        }
        else {
            label = `${prefix} (${method.returnType})${method.selector}`;
        }
        const sig = new vscode.SignatureInformation(label, `${containerName}`);
        sig.parameters = params;
        return sig;
    }
}
exports.ObjJSignatureHelpProvider = ObjJSignatureHelpProvider;
//# sourceMappingURL=signatureHelp.js.map