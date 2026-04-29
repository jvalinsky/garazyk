# Syntax Highlighting Configuration

This document describes the syntax highlighting configuration for the VitePress documentation site.

## Configuration Summary

The syntax highlighting is configured in `.vitepress/config.ts` using Shiki, VitePress's built-in syntax highlighter.

### Key Settings

```typescript
markdown: {
  lineNumbers: true,
  theme: {
    light: 'github-light',
    dark: 'github-dark'
  },
  languageAlias: {
    'objectivec': 'objective-c',
    'objc': 'objective-c'
  }
}
```

## Features

### 1. Line Numbers
- **Status**: ✅ Enabled
- **Configuration**: `lineNumbers: true`
- All code blocks display line numbers on the left side for easy reference

### 2. Dual Theme Support
- **Light Theme**: `github-light` - Clean, readable syntax highlighting for light mode
- **Dark Theme**: `github-dark` - Eye-friendly syntax highlighting for dark mode
- Themes automatically switch based on user preference

### 3. Language Support

#### Primary Languages
- **Objective-C**: Full support with language aliases (`objective-c`, `objectivec`, `objc`)
- **TypeScript**: Native support for configuration files and examples
- **Bash**: Native support for shell scripts and build commands
- **JSON**: Native support for configuration examples

#### Language Aliases
The following aliases are configured for Objective-C:
- `objectivec` → `objective-c`
- `objc` → `objective-c`

This ensures code blocks work regardless of which variant is used in markdown.

### 4. Unsupported Languages
Some specialized languages are not supported by Shiki and have been converted:
- **PromQL**: Converted to `yaml` for Prometheus query examples (in `docs/11-reference/alerting.md`)
- **DOT**: Would need to be converted to `plaintext` if used

## Testing

A comprehensive test page is available at `docs/test-syntax-highlighting.md` that verifies:
- Line numbers display correctly
- All four primary languages render with proper syntax highlighting
- Both light and dark themes work correctly
- Code is readable with sufficient contrast

## Usage in Documentation

### Basic Code Block
```markdown
```objective-c
#import <Foundation/Foundation.h>

@interface MyClass : NSObject
@end
\```
```

### With Language Alias
```markdown
```objc
// This also works
\```
```

## Task 5.1 Validation

This configuration satisfies all requirements from task 5.1:

1. ✅ **Shiki configured** with Objective-C support via language aliases
2. ✅ **Light theme** set to `github-light`
3. ✅ **Dark theme** set to `github-dark`
4. ✅ **Line numbers enabled** for all code blocks
5. ✅ **Tested languages**: Objective-C, TypeScript, Bash, JSON all working correctly

## Future Enhancements

The `config` function in the markdown configuration is prepared for Phase 4 enhancements:
- Line highlighting support (`{2,4-6}` syntax)
- Code block titles (`[filename.m]` syntax)
- Code group tabs for platform-specific examples
- Copy-to-clipboard buttons
- Code annotations

These will be implemented in subsequent tasks (5.2-5.6).
