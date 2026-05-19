export { runSmoke } from "./smoke_command.ts";
export {
  CloudflareClient,
  runBackfill,
  runBackup,
  runDnsAdd,
  runSetupPds,
  runValidateConfig,
} from "./ops_command.ts";
export type {
  BackfillOptions,
  BackupOptions,
  DnsAddOptions,
  SetupPdsOptions,
  ValidateConfigOptions,
} from "./ops_command.ts";
export * from "./doc_coverage.ts";
export * from "./doc_validator.ts";
export {
  buildReport as buildTsdocCoverageReport,
  collectSourceFiles,
  loadDocJson,
  main as tsdocCoverageMain,
  printReport as printTsdocCoverageReport,
} from "./tsdoc_coverage.ts";
export type {
  CoverageBucket,
  CoverageItem,
  CoverageReport,
  JsDoc,
  JsDocTag,
  SourceLocation,
  SymbolKind,
} from "./tsdoc_coverage.ts";
export {
  analyzeLinks,
  buildRegistry,
  checkExternalLinks,
  classifyDoc as repoDocsClassifyDoc,
  computeOrphans,
  createRepoDocsPaths,
  discoverMarkdownFiles,
  generateIndexPages,
  inferCanonicalTarget as repoDocsInferCanonicalTarget,
  inferOwner as repoDocsInferOwner,
  main as repoDocsMain,
  resolveInternalTarget,
  walkMarkdown,
} from "./repo_docs.ts";
export type {
  Classification,
  DocRecord,
  ExternalLinkReport,
  ExternalLinkResult,
  LinkAnalysis,
  LinkEdge,
  LinkIssue,
  LinkStats,
  OrphanAnalysis,
  RepoDocsPaths,
} from "./repo_docs.ts";
export {
  checkBoundaries,
  lineForOffset,
  lineStartOffsets,
  main as boundaryCheckMain,
  walkTypeScriptFiles,
} from "./boundary_check.ts";
export type { BoundaryRule, PackageName, Violation } from "./boundary_check.ts";
export {
  addSpdxHeader,
  hasSpdx,
  main as spdxHeadersMain,
  processFile as processSpdxFile,
  walk as walkSpdx,
} from "./spdx_headers.ts";
export {
  main as vitepressMigrationMain,
  MigrationTool,
} from "./vitepress_migration.ts";
export type {
  FileInfo,
  MigrationError,
  MigrationOptions,
  MigrationResult,
} from "./vitepress_migration.ts";
