# Objective-J Language Support for VS Code

Rich language support for [Objective-J](https://www.cappuccino.dev/learn/objective-j.html), the programming language used by the [Cappuccino](https://www.cappuccino.dev/) web application framework.

## Features

### Syntax Highlighting

Full TextMate grammar covering all Objective-J constructs:

- **Class definitions**: `@implementation`, `@end`, categories, protocols
- **Method signatures**: instance (`-`) and class (`+`) methods with typed parameters
- **Message sends**: `[object message:arg]` bracket notation
- **Imports**: `@import <Framework/Class.j>` and `@import "Local.j"`
- **Objective-J keywords**: `@selector`, `@accessors`, `@outlet`, `@action`, `@class`, `@global`, `@typedef`, `@ref`, `@deref`
- **Objective-J literals**: `@"strings"`, `@{dictionaries}`, `@[arrays]`, `YES`, `NO`, `nil`
- **Cappuccino types**: `CPObject`, `CPView`, `CPString`, `CGRect`, and many more
- **Instance variables** with `@accessors` support
- **Embedded JavaScript**: full JS keyword/operator/literal highlighting
- **CG functions**: `CGRectMake`, `CGPointMake`, `CGSizeMake`, etc.

### Code Intelligence

| Feature | Description |
|---------|-------------|
| **Go to Definition** | Jump to class, protocol, and method definitions |
| **Find References** | Find all references to classes, selectors, and symbols |
| **Hover Information** | Class hierarchy, methods, protocol info, outlet connections |
| **Completions** | Superclass-aware method completions, `@import` path autocomplete |
| **Diagnostics** | Warnings for unmatched `@implementation`/`@end`, duplicates, unresolved imports |
| **Code Actions** | Add missing `@import`, generate method stubs |
| **Rename Symbol** | Rename classes and selectors across all files |
| **Signature Help** | Parameter info popup when typing message sends |
| **Semantic Highlighting** | Distinguishes ivars, locals, globals, class vs instance methods |
| **Document Symbols** | `Cmd+Shift+O` with `@:` filtering for methods only |
| **Workspace Symbols** | `Cmd+T` to search all classes/protocols across the workspace |

### Formatting

Auto-format Objective-J files with:

- Proper indentation for `@implementation`/`@end` blocks
- Colon alignment in multi-parameter method signatures
- Method body indentation
- Ivar block formatting

### Code Folding

Structure-aware folding for:

- `@implementation`/`@protocol` blocks
- Method bodies
- Ivar blocks
- Import groups
- Multi-line comments

### Cib/xib File Awareness

- Detects `@outlet` connections in Cib/xib files
- Hover information shows which Cib files reference each outlet
- Hints for outlets not found in any Cib file

### Code Snippets

Quick-insert common patterns:

| Prefix | Description |
|--------|-------------|
| `@impl` | Class implementation with ivars |
| `@impn` | Class implementation (no ivars) |
| `@impf` | Framework import |
| `@impo` | Local import |
| `@sel` | `@selector()` |
| `@acc` | `@accessors()` |
| `@prot` | Protocol definition |
| `@cat` | Category |
| `-method` | Instance method |
| `+method` | Class method |
| `init` | Standard init method |
| `initWith` | Custom init with parameter |
| `alloc` | `[[Class alloc] init]` |
| `@action` | Action method |
| `@class` | Forward class declaration |
| `@typedef` | Type definition |
| `@dict` | Dictionary literal |
| `awake` | `awakeFromCib` method |

### Language Configuration

- Line comments (`//`) and block comments (`/* */`) toggling
- Auto-closing brackets, parentheses, quotes
- Smart indentation rules

## File Associations

- `.j` — Objective-J source files
- `.sj` — Objective-J source files

## Installation

### From VS Code Marketplace

Search for "Objective-J" in the Extensions view (`Cmd+Shift+X`).

### From VSIX

```bash
cd vscode-objective-j
npm install
npm run package
code --install-extension objective-j-0.3.0.vsix
```

### From Source (Development)

1. Clone or copy the `vscode-objective-j` folder
2. Run `npm install`
3. Press `F5` to launch the Extension Development Host
4. Open any `.j` file to see all features in action

## About Objective-J

Objective-J is a superset of JavaScript that adds Objective-C-style syntax including classes, message passing, protocols, and categories. It powers the [Cappuccino](https://www.cappuccino.dev/) framework for building desktop-class web applications.

## License

MIT
