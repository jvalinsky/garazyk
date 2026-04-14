import * as vscode from "vscode";
import { ObjJWorkspaceIndex } from "./index";

/**
 * Provides Cib/xib file awareness for Objective-J.
 *
 * Cappuccino uses .cib files (compiled Interface Builder files, JSON or plist)
 * and sometimes .xib files.  This provider does best-effort text matching to
 * detect outlet references inside those files and cross-references them against
 * @outlet declarations found by the Objective-J parser.
 */
export class ObjJCibProvider {
  private cibFiles: Map<string, string> = new Map(); // uri.toString() -> content
  private diagnosticCollection: vscode.DiagnosticCollection;
  private watchers: vscode.Disposable[] = [];

  constructor(private index: ObjJWorkspaceIndex) {
    this.diagnosticCollection = vscode.languages.createDiagnosticCollection("objective-j-cib");
  }

  dispose(): void {
    this.diagnosticCollection.dispose();
    for (const w of this.watchers) {
      w.dispose();
    }
  }

  /**
   * Scan the workspace for .cib and .xib files, read their contents, and
   * set up file-system watchers for ongoing changes.
   */
  async indexCibFiles(): Promise<void> {
    const uris = await vscode.workspace.findFiles("**/*.{cib,xib}", "**/node_modules/**");
    await Promise.all(uris.map((uri) => this.readCibFile(uri)));
  }

  /**
   * Start watching for .cib/.xib file changes.
   * Returns disposables that should be pushed into context.subscriptions.
   */
  watch(): vscode.Disposable[] {
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
  getOutletConnections(className: string, outletName: string): string[] {
    const matches: string[] = [];

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
  provideOutletHover(className: string, ivarName: string): string | undefined {
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
  diagnoseOutlets(): void {
    for (const { cls, uri } of this.index.allClasses()) {
      const outletIvars = cls.ivars.filter((ivar) => ivar.isOutlet);
      if (outletIvars.length === 0) continue;

      const diagnostics: vscode.Diagnostic[] = [];

      for (const ivar of outletIvars) {
        const connections = this.getOutletConnections(cls.name, ivar.name);
        if (connections.length === 0) {
          const diag = new vscode.Diagnostic(
            ivar.nameRange,
            `@outlet '${ivar.name}' (${ivar.type}) is not referenced in any Cib/xib file`,
            vscode.DiagnosticSeverity.Hint
          );
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

  private async readCibFile(uri: vscode.Uri): Promise<void> {
    try {
      const bytes = await vscode.workspace.fs.readFile(uri);
      this.cibFiles.set(uri.toString(), Buffer.from(bytes).toString("utf-8"));
    } catch {
      this.cibFiles.delete(uri.toString());
    }
  }
}
