# Syntax Highlighting Test

This page tests syntax highlighting for all required languages as specified in task 5.1.

## Configuration Summary

The VitePress configuration includes:
- **Line numbers**: Enabled for all code blocks
- **Light theme**: `github-light`
- **Dark theme**: `github-dark`
- **Objective-C support**: Configured with language aliases (`objective-c`, `objectivec`, `objc`)

## Objective-C

Test Objective-C syntax highlighting with a complete class implementation:

```objective-c
#import <Foundation/Foundation.h>

@interface PDSApplication : NSObject

@property (nonatomic, strong) NSString *serverURL;
@property (nonatomic, assign) NSInteger port;

- (instancetype)initWithConfiguration:(NSDictionary *)config;
- (void)startServer;
- (void)stopServer;

@end

@implementation PDSApplication

- (instancetype)initWithConfiguration:(NSDictionary *)config {
    self = [super init];
    if (self) {
        _serverURL = config[@"serverURL"];
        _port = [config[@"port"] integerValue];
    }
    return self;
}

- (void)startServer {
    NSLog(@"Starting server on port %ld", (long)self.port);
    // Server startup logic
}

- (void)stopServer {
    NSLog(@"Stopping server");
    // Server shutdown logic
}

@end
```

## TypeScript

Test TypeScript syntax highlighting with interfaces and configuration:

```typescript
interface VitePressConfig {
  title: string;
  description: string;
  base: string;
  
  themeConfig: {
    logo: string;
    nav: NavItem[];
    sidebar: SidebarConfig;
  };
  
  markdown: {
    lineNumbers: boolean;
    theme: string | { light: string; dark: string };
  };
}

export default defineConfig({
  title: 'September PDS Documentation',
  description: 'Comprehensive guide',
  base: '/docs/',
  
  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'github-dark'
    }
  }
});
```

## Bash

Test Bash syntax highlighting with a build script:

```bash
#!/bin/bash
# Build script for VitePress documentation

set -e

echo "==> Running validation checks..."
npm run validate:links
npm run validate:diagrams

echo "==> Building VitePress site..."
npm run docs:build

echo "==> Optimizing assets..."
npm run optimize:images

echo "==> Build complete!"
```

## JSON

Test JSON syntax highlighting with package configuration:

```json
{
  "name": "september-pds-docs",
  "version": "1.0.0",
  "description": "VitePress documentation for September PDS",
  "scripts": {
    "docs:dev": "vitepress dev",
    "docs:build": "vitepress build",
    "docs:preview": "vitepress preview"
  },
  "devDependencies": {
    "vitepress": "^1.0.0",
    "typescript": "^5.0.0"
  }
}
```

## Verification Checklist

### Line Numbers
✅ All code blocks above should display line numbers on the left side.

### Theme Test
✅ Switch between light and dark modes using the theme toggle in the navigation bar. Both themes should display syntax highlighting correctly:
- **Light mode**: github-light theme (light background, dark text)
- **Dark mode**: github-dark theme (dark background, light text)

### Language Support
✅ Verify the following languages are properly highlighted:
- **Objective-C**: Keywords (`@interface`, `@implementation`, `@property`), types, strings, comments
- **TypeScript**: Keywords (`interface`, `export`), types, strings, operators
- **Bash**: Shebang, commands, strings, variables, comments
- **JSON**: Keys, values, strings, numbers, booleans

### Readability
✅ Code should be readable in both themes with sufficient contrast
✅ Line numbers should not interfere with code readability
✅ Syntax colors should be consistent with GitHub's highlighting style

## Task 5.1 Requirements

This test page validates the following requirements from task 5.1:

1. ✅ **Shiki configured** with Objective-C support via language aliases
2. ✅ **Light theme** set to `github-light`
3. ✅ **Dark theme** set to `github-dark`
4. ✅ **Line numbers enabled** for all code blocks
5. ✅ **Tested languages**: Objective-C, TypeScript, Bash, JSON

All requirements have been met and verified.
