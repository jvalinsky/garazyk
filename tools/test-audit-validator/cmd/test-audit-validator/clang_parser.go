package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	gclang "github.com/go-clang/clang-v14/clang"
	"github.com/september-pds/test-audit-validator/internal/analysis"
	"github.com/september-pds/test-audit-validator/internal/config"
	"github.com/september-pds/test-audit-validator/internal/models"
)

type clangFileParser struct {
	rootDirectory      string
	compileCommandsDir string
	extraArgs          []string
}

var (
	compileCommandsCacheMu sync.Mutex
	compileCommandsCache   = map[string]map[string][]string{}
)

func newClangFileParser(cfg *config.Config) *clangFileParser {
	ccDir := strings.TrimSpace(cfg.CompileCommandsDir)
	if ccDir == "" {
		ccDir = discoverCompileCommandsDir(cfg.RootDirectory)
	}

	return &clangFileParser{
		rootDirectory:      cfg.RootDirectory,
		compileCommandsDir: ccDir,
		extraArgs:          append([]string(nil), cfg.ClangArgs...),
	}
}

func (p *clangFileParser) analyze(filePath string) (*models.TestFile, error) {
	engine := analysis.NewStaticAnalysisEngine()
	defer engine.Close()

	args, fullArgv := p.resolveCommandLineArgs(filePath)
	if fullArgv {
		args = normalizeFullArgvCompiler(args)
	}

	tu, err := engine.ParseFileWithCommandLine(filePath, args, fullArgv)
	if err != nil && fullArgv && isASTReadError(err) {
		if tu.IsValid() {
			tu.Dispose()
		}
		retryArgs := compileCommandArgsForParse(filePath, args)
		if len(retryArgs) > 0 {
			tu, err = engine.ParseFileWithCommandLine(filePath, retryArgs, false)
		}
	}
	// Only fail when the translation unit itself is invalid (fatal parse failure).
	// A valid TU with diagnostic errors (e.g. unresolved headers) can still yield
	// accurate method/assertion structure, so we proceed with partial analysis
	// rather than falling back to the simple regex parser.
	if err != nil && !tu.IsValid() {
		return nil, err
	}
	defer tu.Dispose()

	return p.buildTestFileFromTU(filePath, tu, engine)
}

func (p *clangFileParser) resolveCommandLineArgs(filePath string) ([]string, bool) {
	if p.compileCommandsDir != "" {
		if args, ok := loadCompileCommandArgs(p.compileCommandsDir, filePath); ok {
			args = ensureXCTestFrameworkArgs(args)
			args = appendClangRuntimeArgs(args)
			return append(args, p.extraArgs...), true
		}
	}

	args := defaultObjCParseArgs()
	args = append(args, p.projectFallbackIncludeArgs(filePath)...)
	args = appendClangRuntimeArgs(args)
	args = append(args, p.extraArgs...)
	return args, false
}

func (p *clangFileParser) buildTestFileFromTU(filePath string, tu gclang.TranslationUnit, engine *analysis.StaticAnalysisEngine) (*models.TestFile, error) {
	content, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", filePath, err)
	}
	allLines := strings.Split(string(content), "\n")

	tf := &models.TestFile{
		Path:    filePath,
		Imports: extractImportsFromContent(content),
	}

	classIndex := make(map[string]int)
	ensureClass := func(className string, baseClass *string) *models.TestClass {
		if idx, ok := classIndex[className]; ok {
			if baseClass != nil && tf.Classes[idx].BaseClass == nil {
				tf.Classes[idx].BaseClass = baseClass
			}
			return &tf.Classes[idx]
		}

		tc := models.TestClass{
			Name:      className,
			FilePath:  filePath,
			BaseClass: baseClass,
			IsHelper:  isHelperTestClass(className),
		}
		tf.Classes = append(tf.Classes, tc)
		classIndex[className] = len(tf.Classes) - 1
		return &tf.Classes[len(tf.Classes)-1]
	}

	root := tu.TranslationUnitCursor()
	walkCursor(root, func(cursor, parent gclang.Cursor) bool {
		switch cursor.Kind() {
		case gclang.Cursor_ObjCInterfaceDecl, gclang.Cursor_ObjCImplementationDecl, gclang.Cursor_ObjCCategoryImplDecl:
			if !cursorBelongsToFile(cursor, filePath) {
				return true
			}
			className := strings.TrimSpace(cursor.Spelling())
			if !looksLikeTestClass(className) {
				return true
			}
			ensureClass(className, extractBaseClass(cursor))
		}
		return true
	})

	seenMethod := make(map[string]struct{})

	walkCursor(root, func(cursor, parent gclang.Cursor) bool {
		kind := cursor.Kind()
		if kind != gclang.Cursor_ObjCInstanceMethodDecl && kind != gclang.Cursor_ObjCClassMethodDecl {
			return true
		}
		if !cursorBelongsToFile(cursor, filePath) {
			return true
		}

		methodName := strings.TrimSpace(cursor.Spelling())
		if !strings.HasPrefix(methodName, "test") {
			return true
		}
		// XCTest methods must be parameterless selectors.
		if strings.Contains(methodName, ":") {
			return true
		}

		semanticParent := cursor.SemanticParent()
		parentKind := semanticParent.Kind()
		if parentKind != gclang.Cursor_ObjCImplementationDecl && parentKind != gclang.Cursor_ObjCCategoryImplDecl {
			return true
		}

		className := strings.TrimSpace(semanticParent.Spelling())
		if className == "" {
			className = strings.TrimSpace(cursor.LexicalParent().Spelling())
		}
		if className == "" || !looksLikeTestClass(className) {
			return true
		}

		location := cursor.Location()
		_, line, _, _ := location.FileLocation()
		lineNumber := int(line)
		seenKey := className + "\x00" + methodName + "\x00" + fmt.Sprintf("%d", lineNumber)
		if _, ok := seenMethod[seenKey]; ok {
			return true
		}
		seenMethod[seenKey] = struct{}{}

		sourceCode := extractSourceForCursor(content, allLines, cursor)
		method := models.TestMethod{
			Name:       methodName,
			ClassName:  className,
			LineNumber: lineNumber,
			SourceCode: sourceCode,
		}

		// Extract comments and inline notes.
		method.Comments = parseRawCommentLines(cursor.RawCommentText())
		addInlineComments(&method)
		if len(method.Comments) == 0 {
			extractCommentsFromSource(&method, allLines, method.LineNumber)
		}
		method.Comments = dedupeStrings(method.Comments)

		// Extract assertions with AST first, and fallback to source scanning
		// when AST extraction yields no assertions.
		if assertions, err := engine.ExtractAssertions(cursor); err == nil && len(assertions) > 0 {
			method.Assertions = engine.AnalyzeControlFlow(cursor, assertions)
		}
		if len(method.Assertions) == 0 && strings.Contains(sourceCode, "XCTAssert") {
			extractAssertionsFromSource(&method)
		}

		if calls, err := engine.ExtractMethodCalls(cursor); err == nil {
			method.MethodCalls = calls
		}

		class := ensureClass(className, extractBaseClass(semanticParent))
		class.Methods = append(class.Methods, method)
		return true
	})

	for i := range tf.Classes {
		sort.Slice(tf.Classes[i].Methods, func(a, b int) bool {
			if tf.Classes[i].Methods[a].LineNumber == tf.Classes[i].Methods[b].LineNumber {
				return tf.Classes[i].Methods[a].Name < tf.Classes[i].Methods[b].Name
			}
			return tf.Classes[i].Methods[a].LineNumber < tf.Classes[i].Methods[b].LineNumber
		})
	}

	return tf, nil
}

func discoverCompileCommandsDir(rootDirectory string) string {
	absRoot, err := filepath.Abs(rootDirectory)
	if err != nil {
		return ""
	}

	for dir := absRoot; ; dir = filepath.Dir(dir) {
		if hasCompileCommands(dir) {
			return dir
		}

		candidates := []string{
			filepath.Join(dir, "build"),
			filepath.Join(dir, "cmake-build"),
			filepath.Join(dir, "cmake-build-debug"),
			filepath.Join(dir, "cmake-build-release"),
		}
		for _, candidate := range candidates {
			if hasCompileCommands(candidate) {
				return candidate
			}
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
	}

	return ""
}

func hasCompileCommands(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "compile_commands.json"))
	return err == nil && !info.IsDir()
}

func loadCompileCommandArgs(compileCommandsDir, filePath string) ([]string, bool) {
	index, ok := loadCompileCommandIndex(compileCommandsDir)
	if !ok {
		return nil, false
	}

	key := normalizePathKey(filePath)
	if key == "" {
		return nil, false
	}
	args, ok := index[key]
	if !ok || len(args) == 0 {
		return nil, false
	}
	return append([]string(nil), args...), true
}

func loadCompileCommandIndex(compileCommandsDir string) (map[string][]string, bool) {
	cacheKey := normalizePathKey(filepath.Join(compileCommandsDir, "compile_commands.json"))
	if cacheKey == "" {
		return nil, false
	}

	compileCommandsCacheMu.Lock()
	cached, ok := compileCommandsCache[cacheKey]
	compileCommandsCacheMu.Unlock()
	if ok {
		return cached, len(cached) > 0
	}

	errCode, db := gclang.FromDirectory(compileCommandsDir)
	if errCode != gclang.CompilationDatabase_NoError {
		return nil, false
	}
	defer db.Dispose()

	commands := db.AllCompileCommands()
	if commands.Size() == 0 {
		return nil, false
	}
	defer commands.Dispose()

	index := make(map[string][]string, commands.Size())
	for i := uint32(0); i < commands.Size(); i++ {
		cmd := commands.Command(i)
		fileKey := normalizePathKey(cmd.Filename())
		if fileKey == "" {
			continue
		}
		if _, exists := index[fileKey]; exists {
			continue
		}

		rawArgs := make([]string, 0, cmd.NumArgs())
		for j := uint32(0); j < cmd.NumArgs(); j++ {
			rawArgs = append(rawArgs, cmd.Arg(j))
		}
		sanitized := sanitizeCompileCommandArgs(rawArgs)
		if len(sanitized) == 0 {
			continue
		}
		index[fileKey] = sanitized
	}

	compileCommandsCacheMu.Lock()
	compileCommandsCache[cacheKey] = index
	compileCommandsCacheMu.Unlock()

	return index, len(index) > 0
}

func normalizePathKey(path string) string {
	if strings.TrimSpace(path) == "" {
		return ""
	}
	abs, err := filepath.Abs(path)
	if err == nil {
		return filepath.Clean(abs)
	}
	return filepath.Clean(path)
}

func shouldAvoidFullArgv(args []string) bool {
	if len(args) == 0 {
		return false
	}

	arg0 := strings.TrimSpace(args[0])
	if arg0 == "" || strings.HasPrefix(arg0, "-") {
		return true
	}

	libclangPath := strings.TrimSpace(os.Getenv("LIBCLANG_PATH"))
	if libclangPath == "" {
		return false
	}

	if strings.Contains(libclangPath, "/nix/store/") && !strings.HasPrefix(arg0, "/nix/store/") {
		return true
	}

	return false
}

func normalizeFullArgvCompiler(args []string) []string {
	if !shouldAvoidFullArgv(args) {
		return args
	}
	clangExecutable := resolveClangExecutable()
	if clangExecutable == "" {
		return args
	}
	out := append([]string(nil), args...)
	out[0] = clangExecutable
	return out
}

func resolveClangExecutable() string {
	candidate := strings.TrimSpace(os.Getenv("CLANG_EXECUTABLE"))
	if candidate != "" {
		return candidate
	}
	candidate, err := exec.LookPath("clang")
	if err != nil {
		return ""
	}
	return candidate
}

func isASTReadError(err error) bool {
	return err != nil && strings.Contains(err.Error(), "ASTReadError")
}

func compileCommandArgsForParse(filePath string, fullArgv []string) []string {
	if len(fullArgv) == 0 {
		return nil
	}

	out := make([]string, 0, len(fullArgv))
	for i, arg := range fullArgv {
		if strings.TrimSpace(arg) == "" {
			continue
		}
		if i == 0 && !strings.HasPrefix(arg, "-") {
			// Drop argv[0] (compiler executable) for ParseTranslationUnit2.
			continue
		}
		if samePath(arg, filePath) {
			// source_filename is already provided separately.
			continue
		}
		out = append(out, arg)
	}

	out = ensureSyntaxOnlyArg(out)
	out = ensureResourceDirArg(out)
	return out
}

func ensureSyntaxOnlyArg(args []string) []string {
	for _, arg := range args {
		if arg == "-fsyntax-only" {
			return args
		}
	}
	return append(args, "-fsyntax-only")
}

func ensureResourceDirArg(args []string) []string {
	for i, arg := range args {
		if arg == "-resource-dir" {
			if i+1 < len(args) && strings.TrimSpace(args[i+1]) != "" {
				return args
			}
			return args
		}
		if strings.HasPrefix(arg, "-resource-dir=") {
			return args
		}
	}

	resourceDir := strings.TrimSpace(os.Getenv("CLANG_RESOURCE_DIR"))
	if resourceDir == "" {
		return args
	}
	return append(args, "-resource-dir", resourceDir)
}

func samePath(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	aAbs, aErr := filepath.Abs(a)
	bAbs, bErr := filepath.Abs(b)
	if aErr == nil && bErr == nil {
		return filepath.Clean(aAbs) == filepath.Clean(bAbs)
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

func sanitizeCompileCommandArgs(args []string) []string {
	if len(args) == 0 {
		return nil
	}

	out := make([]string, 0, len(args))
	skipNext := false

	flagsWithValue := map[string]bool{
		"-o":                     true,
		"-MF":                    true,
		"-MT":                    true,
		"-MQ":                    true,
		"-MJ":                    true,
		"-serialize-diagnostics": true,
		"-dependency-file":       true,
		"--dependency-file":      true,
	}

	flagsToDrop := map[string]bool{
		"-c":              true,
		"-emit-ast":       true,
		"-M":              true,
		"-MM":             true,
		"-MD":             true,
		"-MMD":            true,
		"-MP":             true,
		"-save-temps":     true,
		"-save-temps=cwd": true,
		"-save-temps=obj": true,
	}

	for i, arg := range args {
		if skipNext {
			skipNext = false
			continue
		}
		if strings.TrimSpace(arg) == "" {
			continue
		}

		if i == 0 {
			out = append(out, arg) // compiler executable for full-argv mode
			continue
		}

		if flagsWithValue[arg] {
			skipNext = true
			continue
		}
		if flagsToDrop[arg] {
			continue
		}
		if strings.HasPrefix(arg, "-o") && len(arg) > 2 {
			continue
		}
		if strings.HasPrefix(arg, "-MF") && len(arg) > 3 {
			continue
		}
		if strings.HasPrefix(arg, "-MT") && len(arg) > 3 {
			continue
		}
		if strings.HasPrefix(arg, "-MQ") && len(arg) > 3 {
			continue
		}
		if strings.HasPrefix(arg, "-MJ") && len(arg) > 3 {
			continue
		}
		if strings.HasPrefix(arg, "-fprofile-instr-generate") {
			continue
		}
		if strings.HasPrefix(arg, "-fcoverage-mapping") {
			continue
		}

		out = append(out, arg)
	}

	return out
}

func defaultObjCParseArgs() []string {
	args := []string{
		"-x", "objective-c",
		"-fobjc-arc",
		"-fblocks",
		"-fmodules",
		"-I/usr/include",
		"-I/usr/local/include",
		"-Wno-everything",
	}

	sdkPath := "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
	if _, err := os.Stat(sdkPath); err == nil {
		args = append(args, "-isysroot", sdkPath)
		frameworks := filepath.Join(sdkPath, "System", "Library", "Frameworks")
		if info, fwErr := os.Stat(frameworks); fwErr == nil && info.IsDir() {
			args = append(args, "-F", frameworks, "-iframework", frameworks)
		}
	}

	// XCTest lives in Xcode's platform developer frameworks and is not present
	// in compile_commands.json for repositories that do not compile XCTest bundles
	// through CMake. Include it in fallback parse args to avoid mass fallback.
	xcodeFrameworks := "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
	if info, err := os.Stat(xcodeFrameworks); err == nil && info.IsDir() {
		args = append(args, "-F", xcodeFrameworks, "-iframework", xcodeFrameworks)
	}
	return args
}

func ensureXCTestFrameworkArgs(args []string) []string {
	xcodeFrameworks := "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
	info, err := os.Stat(xcodeFrameworks)
	if err != nil || !info.IsDir() {
		return args
	}

	for i, arg := range args {
		if strings.HasPrefix(arg, "-F") && strings.TrimPrefix(arg, "-F") == xcodeFrameworks {
			return args
		}
		if arg == "-F" && i+1 < len(args) && args[i+1] == xcodeFrameworks {
			return args
		}
	}

	out := append([]string(nil), args...)
	out = append(out, "-F", xcodeFrameworks, "-iframework", xcodeFrameworks)
	return out
}

func appendClangRuntimeArgs(args []string) []string {
	out := append([]string(nil), args...)

	hasArg := func(name string) bool {
		for i, arg := range out {
			if arg == name {
				return true
			}
			if strings.HasPrefix(arg, name+"=") {
				return true
			}
			if i > 0 && out[i-1] == name {
				return true
			}
		}
		return false
	}

	if cachePath := strings.TrimSpace(os.Getenv("CLANG_MODULE_CACHE_PATH")); cachePath != "" && !hasArg("-fmodules-cache-path") {
		out = append(out, "-fmodules-cache-path="+cachePath)
	}
	if resourceDir := strings.TrimSpace(os.Getenv("CLANG_RESOURCE_DIR")); resourceDir != "" && !hasArg("-resource-dir") {
		out = append(out, "-resource-dir", resourceDir)
	}

	return out
}

func (p *clangFileParser) projectFallbackIncludeArgs(filePath string) []string {
	candidates := make([]string, 0, 8)
	candidates = append(candidates, filepath.Dir(filePath))

	rootDir := strings.TrimSpace(p.rootDirectory)
	if rootDir == "" {
		rootDir = filepath.Dir(filePath)
	}
	rootAbs, err := filepath.Abs(rootDir)
	if err == nil {
		parent := filepath.Dir(rootAbs)
		candidates = append(candidates,
			rootAbs,
			parent,
			filepath.Join(rootAbs, "Sources"),
			filepath.Join(parent, "Sources"),
			filepath.Join(rootAbs, "Tests"),
			filepath.Join(parent, "Tests"),
		)
	}

	seen := make(map[string]struct{}, len(candidates))
	args := make([]string, 0, len(candidates)*2)
	for _, dir := range candidates {
		if strings.TrimSpace(dir) == "" {
			continue
		}
		absDir, absErr := filepath.Abs(dir)
		if absErr != nil {
			continue
		}
		info, statErr := os.Stat(absDir)
		if statErr != nil || !info.IsDir() {
			continue
		}
		if _, ok := seen[absDir]; ok {
			continue
		}
		seen[absDir] = struct{}{}
		args = append(args, "-I", absDir)
	}

	return args
}

func walkCursor(cursor gclang.Cursor, visitor func(cursor, parent gclang.Cursor) bool) {
	cursor.Visit(func(child, parent gclang.Cursor) gclang.ChildVisitResult {
		if !visitor(child, parent) {
			return gclang.ChildVisit_Break
		}
		walkCursor(child, visitor)
		return gclang.ChildVisit_Continue
	})
}

func cursorBelongsToFile(cursor gclang.Cursor, filePath string) bool {
	file, _, _, _ := cursor.Location().FileLocation()
	if file.Name() == "" {
		return false
	}

	fileAbs, err := filepath.Abs(file.Name())
	if err != nil {
		return filepath.Clean(file.Name()) == filepath.Clean(filePath)
	}
	targetAbs, err := filepath.Abs(filePath)
	if err != nil {
		return filepath.Clean(file.Name()) == filepath.Clean(filePath)
	}
	return filepath.Clean(fileAbs) == filepath.Clean(targetAbs)
}

func looksLikeTestClass(className string) bool {
	return strings.Contains(className, "Test") || strings.HasSuffix(className, "Tests")
}

func isHelperTestClass(className string) bool {
	name := strings.ToLower(className)
	patterns := []string{"helper", "util", "base", "common", "fixture", "mock", "stub", "fake"}
	for _, pattern := range patterns {
		if strings.Contains(name, pattern) {
			return true
		}
	}
	return strings.HasSuffix(className, "Base")
}

func extractBaseClass(cursor gclang.Cursor) *string {
	var base *string
	cursor.Visit(func(child, parent gclang.Cursor) gclang.ChildVisitResult {
		if child.Kind() == gclang.Cursor_ObjCSuperClassRef {
			name := strings.TrimSpace(child.Spelling())
			if name != "" {
				base = &name
				return gclang.ChildVisit_Break
			}
		}
		return gclang.ChildVisit_Continue
	})
	return base
}

func extractSourceForCursor(content []byte, allLines []string, cursor gclang.Cursor) string {
	extent := cursor.Extent()
	_, startLine, _, startOffset := extent.Start().FileLocation()
	_, endLine, _, endOffset := extent.End().FileLocation()

	start := int(startOffset)
	end := int(endOffset)
	if start >= 0 && end > start && end <= len(content) {
		return string(content[start:end])
	}

	sLine := int(startLine)
	eLine := int(endLine)
	if sLine > 0 && eLine >= sLine && eLine <= len(allLines) {
		return strings.Join(allLines[sLine-1:eLine], "\n")
	}
	return ""
}

func extractImportsFromContent(content []byte) []string {
	lines := strings.Split(string(content), "\n")
	imports := make([]string, 0, 16)
	seen := make(map[string]struct{}, 16)
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#import ") || strings.HasPrefix(trimmed, "#include ") {
			if _, ok := seen[trimmed]; !ok {
				seen[trimmed] = struct{}{}
				imports = append(imports, trimmed)
			}
		}
	}
	return imports
}

func parseRawCommentLines(raw string) []string {
	if raw == "" {
		return nil
	}
	lines := strings.Split(raw, "\n")
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		trimmed = strings.TrimPrefix(trimmed, "//")
		trimmed = strings.TrimPrefix(trimmed, "/*")
		trimmed = strings.TrimSuffix(trimmed, "*/")
		trimmed = strings.TrimPrefix(trimmed, "*")
		trimmed = strings.TrimSpace(trimmed)
		if trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func addInlineComments(method *models.TestMethod) {
	if method.SourceCode == "" {
		return
	}
	for _, line := range strings.Split(method.SourceCode, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			method.Comments = append(method.Comments, trimmed)
		}
	}
}

func dedupeStrings(values []string) []string {
	if len(values) < 2 {
		return values
	}
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}
