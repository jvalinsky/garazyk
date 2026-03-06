package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestShouldAvoidFullArgv_NixLibclangWithXcodeCompiler(t *testing.T) {
	t.Setenv("LIBCLANG_PATH", "/nix/store/abc-libclang/lib")

	args := []string{
		"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
		"-DDEBUG=1",
	}

	if !shouldAvoidFullArgv(args) {
		t.Fatalf("expected full argv to be avoided for xcode compiler with nix libclang")
	}
}

func TestShouldAvoidFullArgv_NixLibclangWithNixCompiler(t *testing.T) {
	t.Setenv("LIBCLANG_PATH", "/nix/store/abc-libclang/lib")

	args := []string{
		"/nix/store/xyz-clang/bin/clang",
		"-DDEBUG=1",
	}

	if shouldAvoidFullArgv(args) {
		t.Fatalf("expected full argv to be allowed for nix compiler with nix libclang")
	}
}

func TestNormalizeFullArgvCompiler_RewritesToConfiguredClang(t *testing.T) {
	t.Setenv("LIBCLANG_PATH", "/nix/store/abc-libclang/lib")
	t.Setenv("CLANG_EXECUTABLE", "/nix/store/xyz-clang/bin/clang")

	args := []string{
		"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
		"-DDEBUG=1",
	}

	got := normalizeFullArgvCompiler(args)
	want := []string{
		"/nix/store/xyz-clang/bin/clang",
		"-DDEBUG=1",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected rewritten full argv:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCompileCommandArgsForParse_DropsCompilerAndSource_AddsSyntaxOnly(t *testing.T) {
	t.Setenv("CLANG_RESOURCE_DIR", "")

	filePath := filepath.Join(t.TempDir(), "ExampleTests.m")
	fullArgv := []string{
		"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
		"-DDEBUG=1",
		"-x",
		"objective-c",
		filePath,
	}

	got := compileCommandArgsForParse(filePath, fullArgv)
	want := []string{
		"-DDEBUG=1",
		"-x",
		"objective-c",
		"-fsyntax-only",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected parse args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestSanitizeCompileCommandArgs_DropsCodegenOnlyFlags(t *testing.T) {
	args := []string{
		"clang",
		"-DDEBUG=1",
		"-fprofile-instr-generate",
		"-fcoverage-mapping",
		"-o",
		"file.o",
		"-c",
		"/tmp/File.m",
	}

	got := sanitizeCompileCommandArgs(args)
	want := []string{
		"clang",
		"-DDEBUG=1",
		"/tmp/File.m",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected sanitized args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCompileCommandArgsForParse_AddsResourceDirFromEnv(t *testing.T) {
	t.Setenv("CLANG_RESOURCE_DIR", "/nix/store/example-clang/lib/clang/18")

	filePath := filepath.Join(t.TempDir(), "ResourceTests.m")
	fullArgv := []string{
		"/usr/bin/clang",
		"-x",
		"objective-c",
		filePath,
	}

	got := compileCommandArgsForParse(filePath, fullArgv)
	want := []string{
		"-x",
		"objective-c",
		"-fsyntax-only",
		"-resource-dir",
		"/nix/store/example-clang/lib/clang/18",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected parse args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestProjectFallbackIncludeArgs_CollectsExistingCandidates(t *testing.T) {
	repoRoot := t.TempDir()
	projectRoot := filepath.Join(repoRoot, "ATProtoPDS")
	testsRoot := filepath.Join(projectRoot, "Tests")
	sourcesRoot := filepath.Join(projectRoot, "Sources")
	filePath := filepath.Join(testsRoot, "App", "ExampleTests.m")

	for _, dir := range []string{
		filepath.Dir(filePath),
		testsRoot,
		sourcesRoot,
		projectRoot,
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}
	if err := os.WriteFile(filePath, []byte("@implementation ExampleTests @end\n"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	p := &clangFileParser{rootDirectory: testsRoot}
	args := p.projectFallbackIncludeArgs(filePath)

	includes := make(map[string]struct{}, len(args)/2)
	for i := 0; i+1 < len(args); i += 2 {
		if strings.TrimSpace(args[i]) != "-I" {
			t.Fatalf("unexpected flag at index %d: %q", i, args[i])
		}
		includes[args[i+1]] = struct{}{}
	}

	for _, required := range []string{
		filepath.Dir(filePath),
		testsRoot,
		projectRoot,
		sourcesRoot,
	} {
		if _, ok := includes[required]; !ok {
			t.Fatalf("expected include path %q in %#v", required, includes)
		}
	}
}

func TestAppendClangRuntimeArgs_AddsModuleCacheAndResourceDir(t *testing.T) {
	t.Setenv("CLANG_MODULE_CACHE_PATH", "/tmp/clang-module-cache")
	t.Setenv("CLANG_RESOURCE_DIR", "/tmp/clang-resource")

	got := appendClangRuntimeArgs([]string{"clang", "-x", "objective-c"})
	want := []string{
		"clang", "-x", "objective-c",
		"-fmodules-cache-path=/tmp/clang-module-cache",
		"-resource-dir", "/tmp/clang-resource",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected runtime args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestAppendClangRuntimeArgs_DoesNotDuplicateExistingFlags(t *testing.T) {
	t.Setenv("CLANG_MODULE_CACHE_PATH", "/tmp/clang-module-cache")
	t.Setenv("CLANG_RESOURCE_DIR", "/tmp/clang-resource")

	input := []string{
		"clang",
		"-fmodules-cache-path=/custom/cache",
		"-resource-dir", "/custom/resource",
	}
	got := appendClangRuntimeArgs(input)

	if !reflect.DeepEqual(got, input) {
		t.Fatalf("expected unchanged args:\n got: %#v\nwant: %#v", got, input)
	}
}

func TestEnsureXCTestFrameworkArgs_AddsDeveloperFrameworkPath(t *testing.T) {
	xcodeFrameworks := "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
	if _, err := os.Stat(xcodeFrameworks); err != nil {
		t.Skip("xcode developer frameworks not present")
	}

	got := ensureXCTestFrameworkArgs([]string{"clang", "-x", "objective-c"})

	wantSuffix := []string{
		"-F", xcodeFrameworks,
		"-iframework", xcodeFrameworks,
	}

	if len(got) < len(wantSuffix) {
		t.Fatalf("unexpected args length: %#v", got)
	}
	if !reflect.DeepEqual(got[len(got)-len(wantSuffix):], wantSuffix) {
		t.Fatalf("expected args to end with XCTest framework suffix:\n got: %#v", got)
	}
}

func TestEnsureXCTestFrameworkArgs_DoesNotDuplicate(t *testing.T) {
	xcodeFrameworks := "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
	if _, err := os.Stat(xcodeFrameworks); err != nil {
		t.Skip("xcode developer frameworks not present")
	}

	input := []string{
		"clang",
		"-F", xcodeFrameworks,
	}
	got := ensureXCTestFrameworkArgs(input)
	if !reflect.DeepEqual(got, input) {
		t.Fatalf("expected unchanged args:\n got: %#v\nwant: %#v", got, input)
	}
}

func TestLoadCompileCommandArgs_UnknownFileReturnsFalse(t *testing.T) {
	tmpDir := t.TempDir()
	known := filepath.Join(tmpDir, "Known.m")
	unknown := filepath.Join(tmpDir, "Unknown.m")

	content := []map[string]interface{}{
		{
			"directory": tmpDir,
			"file":      known,
			"arguments": []string{"clang", "-x", "objective-c", "-c", known, "-o", "Known.o"},
		},
	}
	data, err := json.Marshal(content)
	if err != nil {
		t.Fatalf("marshal compile_commands: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "compile_commands.json"), data, 0o644); err != nil {
		t.Fatalf("write compile_commands.json: %v", err)
	}

	_, ok := loadCompileCommandArgs(tmpDir, unknown)
	if ok {
		t.Fatalf("expected no compile command match for %s", unknown)
	}
}

func TestLoadCompileCommandArgs_KnownFileReturnsSanitizedArgs(t *testing.T) {
	tmpDir := t.TempDir()
	known := filepath.Join(tmpDir, "Known.m")

	content := []map[string]interface{}{
		{
			"directory": tmpDir,
			"file":      known,
			"arguments": []string{"clang", "-x", "objective-c", "-c", known, "-o", "Known.o"},
		},
	}
	data, err := json.Marshal(content)
	if err != nil {
		t.Fatalf("marshal compile_commands: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "compile_commands.json"), data, 0o644); err != nil {
		t.Fatalf("write compile_commands.json: %v", err)
	}

	args, ok := loadCompileCommandArgs(tmpDir, known)
	if !ok {
		t.Fatalf("expected compile command match for %s", known)
	}
	want := []string{"clang", "-x", "objective-c", known}
	if !reflect.DeepEqual(args, want) {
		t.Fatalf("unexpected args:\n got: %#v\nwant: %#v", args, want)
	}
}
