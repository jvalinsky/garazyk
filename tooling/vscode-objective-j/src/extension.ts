import * as vscode from "vscode";
import * as path from "path";
import { parseDocument, ObjJClass, ObjJProtocol } from "./parser";
import { ObjJWorkspaceIndex } from "./index";
import { ObjJDiagnosticProvider } from "./diagnostics";
import { ObjJCodeActionProvider } from "./codeActions";
import { ObjJRenameProvider } from "./rename";
import { ObjJSemanticTokenProvider, LEGEND } from "./semanticTokens";
import { ObjJSignatureHelpProvider } from "./signatureHelp";
import { ObjJDocumentFormattingEditProvider, ObjJDocumentRangeFormattingEditProvider } from "./formatter";
import { ObjJFoldingRangeProvider } from "./folding";
import { ObjJCibProvider } from "./cib";

const OBJJ_SELECTOR: vscode.DocumentSelector = { language: "objective-j", scheme: "file" };
let workspaceIndex: ObjJWorkspaceIndex;
let diagnosticProvider: ObjJDiagnosticProvider;
let cibProvider: ObjJCibProvider;

export function activate(context: vscode.ExtensionContext): void {
  workspaceIndex = new ObjJWorkspaceIndex();
  diagnosticProvider = new ObjJDiagnosticProvider(workspaceIndex);
  cibProvider = new ObjJCibProvider(workspaceIndex);

  // Initial workspace indexing
  workspaceIndex.indexWorkspace().then(async () => {
    // Run diagnostics on all open editors after indexing
    for (const editor of vscode.window.visibleTextEditors) {
      if (editor.document.languageId === "objective-j") {
        diagnosticProvider.diagnose(editor.document);
      }
    }
    // Index Cib/xib files and diagnose outlet connections
    await cibProvider.indexCibFiles();
    cibProvider.diagnoseOutlets();
  });

  // Watch for file changes
  const watcher = vscode.workspace.createFileSystemWatcher("**/*.j");
  watcher.onDidChange((uri) => workspaceIndex.indexFile(uri));
  watcher.onDidCreate((uri) => workspaceIndex.indexFile(uri));
  watcher.onDidDelete((uri) => {
    workspaceIndex.removeFile(uri);
    diagnosticProvider.clear(uri);
  });
  context.subscriptions.push(watcher);

  // Watch for Cib/xib file changes
  context.subscriptions.push(...cibProvider.watch());

  // Re-index + diagnose on document change and save
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.languageId === "objective-j") {
        workspaceIndex.indexDocument(doc);
        diagnosticProvider.diagnose(doc);
        cibProvider.diagnoseOutlets();
      }
    }),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.document.languageId === "objective-j") {
        workspaceIndex.indexDocument(e.document);
      }
    }),
    vscode.workspace.onDidOpenTextDocument((doc) => {
      if (doc.languageId === "objective-j") {
        workspaceIndex.indexDocument(doc);
        diagnosticProvider.diagnose(doc);
      }
    })
  );

  // Register all providers
  context.subscriptions.push(
    // Phase 1: existing providers
    vscode.languages.registerDocumentSymbolProvider(OBJJ_SELECTOR, new ObjJDocumentSymbolProvider()),
    vscode.languages.registerWorkspaceSymbolProvider(new ObjJWorkspaceSymbolProvider()),
    vscode.languages.registerDefinitionProvider(OBJJ_SELECTOR, new ObjJDefinitionProvider()),
    vscode.languages.registerReferenceProvider(OBJJ_SELECTOR, new ObjJReferenceProvider()),
    vscode.languages.registerHoverProvider(OBJJ_SELECTOR, new ObjJHoverProvider()),
    vscode.languages.registerCompletionItemProvider(OBJJ_SELECTOR, new ObjJCompletionProvider(), "[", " ", ":", '"', "<", "/"),

    // Near-term: diagnostics, code actions, rename
    diagnosticProvider,
    vscode.languages.registerCodeActionsProvider(OBJJ_SELECTOR, new ObjJCodeActionProvider(workspaceIndex), {
      providedCodeActionKinds: ObjJCodeActionProvider.providedCodeActionKinds,
    }),
    vscode.languages.registerRenameProvider(OBJJ_SELECTOR, new ObjJRenameProvider(workspaceIndex)),

    // Medium-term: semantic tokens, signature help
    vscode.languages.registerDocumentSemanticTokensProvider(OBJJ_SELECTOR, new ObjJSemanticTokenProvider(workspaceIndex), LEGEND),
    vscode.languages.registerSignatureHelpProvider(OBJJ_SELECTOR, new ObjJSignatureHelpProvider(workspaceIndex), ":", " "),

    // Longer-term: folding, formatting, cib awareness
    vscode.languages.registerFoldingRangeProvider(OBJJ_SELECTOR, new ObjJFoldingRangeProvider()),
    vscode.languages.registerDocumentFormattingEditProvider(OBJJ_SELECTOR, new ObjJDocumentFormattingEditProvider()),
    vscode.languages.registerDocumentRangeFormattingEditProvider(OBJJ_SELECTOR, new ObjJDocumentRangeFormattingEditProvider()),
    cibProvider
  );
}

export function deactivate(): void { }

// ---------------------------------------------------------------------------
// Document Symbol Provider
// ---------------------------------------------------------------------------
class ObjJDocumentSymbolProvider implements vscode.DocumentSymbolProvider {
  provideDocumentSymbols(document: vscode.TextDocument): vscode.DocumentSymbol[] {
    const result = workspaceIndex.indexDocument(document);
    const symbols: vscode.DocumentSymbol[] = [];

    for (const cls of result.classes) {
      symbols.push(classToSymbol(cls));
    }
    for (const proto of result.protocols) {
      symbols.push(protocolToSymbol(proto));
    }
    for (const decl of result.forwardDecls) {
      const kind =
        decl.kind === "class"
          ? vscode.SymbolKind.Class
          : decl.kind === "typedef"
            ? vscode.SymbolKind.TypeParameter
            : vscode.SymbolKind.Variable;
      symbols.push(
        new vscode.DocumentSymbol(`@${decl.kind} ${decl.name}`, "", kind, decl.range, decl.nameRange)
      );
    }

    return symbols;
  }
}

function classToSymbol(cls: ObjJClass): vscode.DocumentSymbol {
  const displayName = cls.category ? `${cls.name} (${cls.category})` : cls.name;
  const detail = cls.superclass ? `: ${cls.superclass}` : "";
  const sym = new vscode.DocumentSymbol(displayName, detail, vscode.SymbolKind.Class, cls.range, cls.nameRange);

  for (const ivar of cls.ivars) {
    sym.children.push(
      new vscode.DocumentSymbol(ivar.name, ivar.type, vscode.SymbolKind.Field, ivar.range, ivar.nameRange)
    );
  }
  for (const method of cls.methods) {
    const prefix = method.isClassMethod ? "+" : "-";
    sym.children.push(
      new vscode.DocumentSymbol(`${prefix} ${method.selector}`, method.returnType, vscode.SymbolKind.Method, method.range, method.selectorRange)
    );
  }

  return sym;
}

function protocolToSymbol(proto: ObjJProtocol): vscode.DocumentSymbol {
  const detail = proto.parentProtocols.length ? `<${proto.parentProtocols.join(", ")}>` : "";
  const sym = new vscode.DocumentSymbol(proto.name, detail, vscode.SymbolKind.Interface, proto.range, proto.nameRange);

  for (const method of proto.methods) {
    const prefix = method.isClassMethod ? "+" : "-";
    sym.children.push(
      new vscode.DocumentSymbol(`${prefix} ${method.selector}`, method.returnType, vscode.SymbolKind.Method, method.range, method.selectorRange)
    );
  }

  return sym;
}

// ---------------------------------------------------------------------------
// Workspace Symbol Provider
// ---------------------------------------------------------------------------
class ObjJWorkspaceSymbolProvider implements vscode.WorkspaceSymbolProvider {
  provideWorkspaceSymbols(query: string): vscode.SymbolInformation[] {
    return workspaceIndex.searchSymbols(query);
  }
}

// ---------------------------------------------------------------------------
// Definition Provider
// ---------------------------------------------------------------------------
class ObjJDefinitionProvider implements vscode.DefinitionProvider {
  provideDefinition(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.Definition | undefined {
    const wordRange = document.getWordRangeAtPosition(position, /@?[a-zA-Z_]\w*/);
    if (!wordRange) return undefined;

    const word = document.getText(wordRange);

    if (/^[A-Z]/.test(word)) {
      const found = workspaceIndex.findClass(word);
      if (found) return new vscode.Location(found.uri, found.cls.nameRange);
      const proto = workspaceIndex.findProtocol(word);
      if (proto) return new vscode.Location(proto.uri, proto.proto.nameRange);
    }

    const line = document.lineAt(position.line).text;
    const selectorMatch = extractSelectorAtPosition(line, position.character);
    if (selectorMatch) {
      const methods = workspaceIndex.findMethodsBySelector(selectorMatch);
      if (methods.length > 0) return methods.map((m) => new vscode.Location(m.uri, m.method.selectorRange));
    }

    const selectorFromMsg = extractSelectorFromMessageSend(line, position.character);
    if (selectorFromMsg) {
      const methods = workspaceIndex.findMethodsBySelector(selectorFromMsg);
      if (methods.length > 0) return methods.map((m) => new vscode.Location(m.uri, m.method.selectorRange));
    }

    return undefined;
  }
}

// ---------------------------------------------------------------------------
// Reference Provider
// ---------------------------------------------------------------------------
class ObjJReferenceProvider implements vscode.ReferenceProvider {
  async provideReferences(
    document: vscode.TextDocument,
    position: vscode.Position,
    context: vscode.ReferenceContext
  ): Promise<vscode.Location[]> {
    const wordRange = document.getWordRangeAtPosition(position, /@?[a-zA-Z_]\w*/);
    if (!wordRange) return [];

    const word = document.getText(wordRange);
    const locations: vscode.Location[] = [];
    const uris = await vscode.workspace.findFiles("**/*.j", "**/node_modules/**");
    const regex = new RegExp(`\\b${escapeRegex(word)}\\b`, "g");

    for (const uri of uris) {
      try {
        const doc = await vscode.workspace.openTextDocument(uri);
        const text = doc.getText();
        let match: RegExpExecArray | null;
        while ((match = regex.exec(text)) !== null) {
          const pos = doc.positionAt(match.index);
          const range = new vscode.Range(pos, doc.positionAt(match.index + word.length));
          if (
            context.includeDeclaration ||
            !(doc.uri.toString() === document.uri.toString() && range.isEqual(wordRange))
          ) {
            locations.push(new vscode.Location(uri, range));
          }
        }
      } catch {
        // skip
      }
    }

    return locations;
  }
}

// ---------------------------------------------------------------------------
// Hover Provider — with superclass chain info
// ---------------------------------------------------------------------------
class ObjJHoverProvider implements vscode.HoverProvider {
  provideHover(document: vscode.TextDocument, position: vscode.Position): vscode.Hover | undefined {
    const wordRange = document.getWordRangeAtPosition(position, /@?[a-zA-Z_]\w*/);
    if (!wordRange) return undefined;

    const word = document.getText(wordRange);

    // --- @outlet ivar hover: show Cib connection info ---
    if (cibProvider) {
      const result = workspaceIndex.indexDocument(document);
      for (const cls of result.classes) {
        if (position.line >= cls.range.start.line && position.line <= cls.range.end.line) {
          const ivar = cls.ivars.find(
            (iv) => iv.isOutlet && iv.nameRange.contains(position)
          );
          if (ivar) {
            const info = cibProvider.provideOutletHover(cls.name, ivar.name);
            if (info) {
              return new vscode.Hover(new vscode.MarkdownString(info));
            }
          }
        }
      }
    }

    if (/^[A-Z]/.test(word)) {
      const found = workspaceIndex.findClass(word);
      if (found) {
        const cls = found.cls;
        const parts: string[] = [];
        const displayName = cls.category ? `${cls.name} (${cls.category})` : cls.name;
        let header = `**@implementation** ${displayName}`;
        if (cls.superclass) header += ` : ${cls.superclass}`;
        if (cls.protocols.length) header += ` <${cls.protocols.join(", ")}>`;
        parts.push(header);

        // Show inheritance chain
        const chain = workspaceIndex.getSuperclassChain(cls.name);
        if (chain.length > 0) {
          parts.push("");
          parts.push(`**Hierarchy:** ${cls.name} → ${chain.join(" → ")}`);
        }

        // Categories
        const categories = workspaceIndex.findCategories(cls.name);
        if (categories.length > 0) {
          parts.push("");
          parts.push(`**Categories:** ${categories.map((c) => c.cls.category).join(", ")}`);
        }

        const allMethods = workspaceIndex.getAllMethodsForClass(cls.name);
        if (allMethods.length > 0) {
          parts.push("");
          const own = allMethods.filter((m) => m.source === cls.name);
          const inherited = allMethods.filter((m) => m.source !== cls.name);
          parts.push(`**Methods** (${own.length} own, ${inherited.length} inherited):`);
          for (const m of own.slice(0, 10)) {
            const prefix = m.method.isClassMethod ? "+" : "-";
            parts.push(`- \`${prefix} (${m.method.returnType})${m.method.selector}\``);
          }
          if (own.length > 10) parts.push(`- ... and ${own.length - 10} more`);
        }

        return new vscode.Hover(new vscode.MarkdownString(parts.join("\n")));
      }

      const proto = workspaceIndex.findProtocol(word);
      if (proto) {
        const p = proto.proto;
        let header = `**@protocol** ${p.name}`;
        if (p.parentProtocols.length) header += ` <${p.parentProtocols.join(", ")}>`;
        const parts = [header];

        if (p.methods.length > 0) {
          parts.push("");
          parts.push(`**Methods** (${p.methods.length}):`);
          for (const m of p.methods) {
            const prefix = m.isClassMethod ? "+" : "-";
            parts.push(`- \`${prefix} (${m.returnType})${m.selector}\``);
          }
        }

        return new vscode.Hover(new vscode.MarkdownString(parts.join("\n")));
      }
    }

    return undefined;
  }
}

// ---------------------------------------------------------------------------
// Completion Provider — superclass-aware + @import path completion
// ---------------------------------------------------------------------------
class ObjJCompletionProvider implements vscode.CompletionItemProvider {
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.CompletionItem[] {
    const line = document.lineAt(position.line).text;
    const textBefore = line.substring(0, position.character);
    const items: vscode.CompletionItem[] = [];

    // --- @import path completion ---
    const localImportMatch = textBefore.match(/@import\s+"([^"]*)$/);
    if (localImportMatch) {
      return this.completeLocalImport(document, localImportMatch[1]);
    }

    const frameworkImportMatch = textBefore.match(/@import\s+<([^>]*)$/);
    if (frameworkImportMatch) {
      return this.completeFrameworkImport(frameworkImportMatch[1]);
    }

    // --- Message send selector completion (superclass-aware) ---
    if (this.isInsideMessageSend(textBefore)) {
      const seenSelectors = new Set<string>();

      // [ClassName ... → class methods with inheritance
      const receiverMatch = textBefore.match(/\[\s*([A-Z]\w*)\s+$/);
      if (receiverMatch) {
        const allMethods = workspaceIndex.getAllMethodsForClass(receiverMatch[1]);
        for (const { method, source } of allMethods) {
          if (method.isClassMethod && !seenSelectors.has(method.selector)) {
            seenSelectors.add(method.selector);
            items.push(this.methodToCompletion(method, source));
          }
        }
        return items;
      }

      // [self/super ... → instance + class methods with inheritance
      const selfMatch = textBefore.match(/\[\s*(?:self|super)\s+$/);
      if (selfMatch) {
        const currentResult = workspaceIndex.getFile(document.uri);
        if (currentResult) {
          for (const cls of currentResult.result.classes) {
            if (position.line >= cls.range.start.line && position.line <= cls.range.end.line) {
              const allMethods = workspaceIndex.getAllMethodsForClass(cls.name);
              for (const { method, source } of allMethods) {
                if (!seenSelectors.has(method.selector)) {
                  seenSelectors.add(method.selector);
                  items.push(this.methodToCompletion(method, source));
                }
              }
            }
          }
        }
        return items;
      }

      // Generic: offer all known selectors
      for (const { cls } of workspaceIndex.allClasses()) {
        for (const m of cls.methods) {
          if (!seenSelectors.has(m.selector)) {
            seenSelectors.add(m.selector);
            items.push(this.methodToCompletion(m, cls.name));
          }
        }
      }
      return items;
    }

    // --- Class/protocol name completion ---
    const wordMatch = textBefore.match(/\b([A-Z]\w*)$/);
    if (wordMatch) {
      const prefix = wordMatch[1].toLowerCase();
      const seenNames = new Set<string>();

      for (const { cls } of workspaceIndex.allClasses()) {
        if (!cls.category && !seenNames.has(cls.name) && cls.name.toLowerCase().startsWith(prefix)) {
          seenNames.add(cls.name);
          const item = new vscode.CompletionItem(cls.name, vscode.CompletionItemKind.Class);
          item.detail = cls.superclass ? `: ${cls.superclass}` : "class";
          items.push(item);
        }
      }
      for (const { proto } of workspaceIndex.allProtocols()) {
        if (!seenNames.has(proto.name) && proto.name.toLowerCase().startsWith(prefix)) {
          seenNames.add(proto.name);
          const item = new vscode.CompletionItem(proto.name, vscode.CompletionItemKind.Interface);
          item.detail = "protocol";
          items.push(item);
        }
      }
    }

    return items;
  }

  private completeLocalImport(document: vscode.TextDocument, partial: string): vscode.CompletionItem[] {
    const items: vscode.CompletionItem[] = [];
    const currentDir = path.dirname(document.uri.fsPath);

    for (const uri of workspaceIndex.allFileUris()) {
      if (uri.toString() === document.uri.toString()) continue;
      const filePath = uri.fsPath;
      let relativePath = path.relative(currentDir, filePath);
      if (!relativePath.startsWith(".")) relativePath = "./" + relativePath;

      if (relativePath.toLowerCase().includes(partial.toLowerCase())) {
        const item = new vscode.CompletionItem(relativePath, vscode.CompletionItemKind.File);
        item.insertText = relativePath;
        item.detail = path.basename(filePath);
        items.push(item);
      }
    }

    return items;
  }

  private completeFrameworkImport(partial: string): vscode.CompletionItem[] {
    const items: vscode.CompletionItem[] = [];

    // Offer known framework paths from indexed files' imports
    const seenPaths = new Set<string>();
    for (const { cls, uri } of workspaceIndex.allClasses()) {
      const file = workspaceIndex.getFile(uri);
      if (!file) continue;
      for (const imp of file.result.imports) {
        if (imp.isFramework && !seenPaths.has(imp.path)) {
          seenPaths.add(imp.path);
          if (imp.path.toLowerCase().includes(partial.toLowerCase())) {
            const item = new vscode.CompletionItem(imp.path, vscode.CompletionItemKind.Module);
            item.insertText = imp.path;
            items.push(item);
          }
        }
      }
    }

    // Also generate framework paths from class definitions
    for (const { cls, uri } of workspaceIndex.allClasses()) {
      if (cls.category) continue;
      const fileName = path.basename(uri.fsPath);
      // Guess framework: Foundation/ClassName.j or AppKit/ClassName.j
      for (const fw of ["Foundation", "AppKit"]) {
        const guessedPath = `${fw}/${fileName}`;
        if (!seenPaths.has(guessedPath) && guessedPath.toLowerCase().includes(partial.toLowerCase())) {
          seenPaths.add(guessedPath);
          const item = new vscode.CompletionItem(guessedPath, vscode.CompletionItemKind.Module);
          item.insertText = guessedPath;
          item.detail = "(suggested)";
          items.push(item);
        }
      }
    }

    return items;
  }

  private isInsideMessageSend(textBefore: string): boolean {
    let depth = 0;
    for (const ch of textBefore) {
      if (ch === "[") depth++;
      if (ch === "]") depth--;
    }
    return depth > 0;
  }

  private methodToCompletion(
    m: { selector: string; isClassMethod: boolean; returnType: string; params: { label: string; type: string; name: string }[] },
    containerName: string
  ): vscode.CompletionItem {
    const prefix = m.isClassMethod ? "+" : "-";
    const item = new vscode.CompletionItem(m.selector, vscode.CompletionItemKind.Method);
    item.detail = `${prefix} (${m.returnType})${m.selector} — ${containerName}`;

    if (m.params.length > 0) {
      const parts = m.params.map((p, idx) => `${p.label}:\${${idx + 1}:${p.name}}`);
      item.insertText = new vscode.SnippetString(parts.join(" "));
    } else {
      item.insertText = m.selector;
    }

    return item;
  }
}

// ---------------------------------------------------------------------------
// Utility functions
// ---------------------------------------------------------------------------
function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extractSelectorAtPosition(line: string, charPos: number): string | undefined {
  const regex = /@selector\(([^)]+)\)/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(line)) !== null) {
    if (charPos >= match.index && charPos <= match.index + match[0].length) {
      return match[1].replace(/\s/g, "");
    }
  }
  return undefined;
}

function extractSelectorFromMessageSend(line: string, charPos: number): string | undefined {
  const parts: string[] = [];
  const labelRegex = /\b([a-zA-Z_]\w*)\s*:/g;
  let match: RegExpExecArray | null;
  while ((match = labelRegex.exec(line)) !== null) {
    parts.push(match[1] + ":");
  }
  if (parts.length > 0) return parts.join("");

  const simpleRegex = /\[\s*\w+\s+([a-zA-Z_]\w*)\s*\]/g;
  while ((match = simpleRegex.exec(line)) !== null) {
    if (charPos >= match.index && charPos <= match.index + match[0].length) {
      return match[1];
    }
  }

  return undefined;
}
