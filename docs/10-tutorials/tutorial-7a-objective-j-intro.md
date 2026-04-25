---
title: "Tutorial 7a: Objective-J for Contributors"
---

# Tutorial 7a: Objective-J for Contributors

## Overview

Garazyk's web UI is built using Objective-J and the Cappuccino framework. While it looks like Objective-C, it runs in the browser on top of the JavaScript runtime. This tutorial provides the necessary language and framework background for contributors to work effectively on the PDS Explorer and Admin UI.

**Learning Objectives:**
- Understand the relationship between Objective-J, Cappuccino, and JavaScript.
- Master the message-send syntax and event-handling patterns.
- Map Cocoa-style Foundation and AppKit classes to their browser equivalents.
- Navigate the mixed Objective-J/JavaScript execution model.

**Estimated Time:** 30-40 minutes

## Prerequisites

- Read [Overview](../01-getting-started/overview) to understand the project's language choices.
- Familiarity with Objective-C or JavaScript syntax.
- `deciduous` CLI tool installed.

## Objective-J and Cappuccino Crash Course

Objective-J looks like Objective-C, but the execution model is much closer to JavaScript running in the browser. In this repo you work across three layers at once:

| Layer | What it gives you | Example in this repo |
| --- | --- | --- |
| Objective-J syntax | Classes, ivars, selectors, message sends | `@implementation AppController : CPObject` |
| Cappuccino framework | Cocoa-style UI and foundation classes | `CPWindow`, `CPView`, `CPTableView`, `CPTextField` |
| JavaScript runtime | Arrays, objects, functions, browser APIs | `[]`, `{}`, `XMLHttpRequest`, `window.setInterval` |

### Where Objective-J Came From

Objective-J and Cappuccino were created together as part of the original 280 North effort to bring Cocoa-style application development to the browser. 

- Cappuccino wanted Foundation/AppKit-style APIs in the browser, not just a pile of DOM helpers.
- Objective-J added Objective-C-like structure on top of JavaScript so Cappuccino code could use classes, imports, selectors, and message sends without leaving the web runtime.
- The design goal was to add missing pieces while staying on top of JavaScript and avoiding a heavy compile cycle.

### How Objective-J Code Is Structured

Most files in the UI follow the same shape:

```objectivec
@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

@implementation ExampleController : CPObject
{
    CPTextField _statusLabel;
    CPArray _accounts;
}
- (id)init
{
    self = [super init];
    if (self)
        _accounts = [];
    return self;
}
- (void)setStatusText:(CPString)text
{
    [_statusLabel setStringValue:text];
}
@end
```

### Message Sends, Selectors, and Colons

Objective-J uses Objective-C message sends:

```objectivec
[_statusLabel setStringValue:@"Idle"];
[lookupButton setTarget:self];
[lookupButton setAction:@selector(handleLookup:)];
```

The trailing colon in `handleLookup:` means the method accepts one argument (usually the sender).

### Objective-J and JavaScript Boundary

Objective-J lives beside JavaScript, not instead of it. You will frequently see them mixed:

```objectivec
- (CPArray)normalizedArrayValue:(id)value
{
    if (value === nil || value === undefined)
        return [];
    if (value instanceof Array)
        return value;
    return [value];
}
```

- `nil` is the Objective-J "no object" value.
- `undefined` comes from JavaScript and browser APIs.
- `instanceof Array` is plain JavaScript type inspection.

### Cappuccino API Map For This Repo

| Area | Primary APIs | Why they matter here |
| --- | --- | --- |
| Object model | `CPObject` | Base class for controllers and API clients |
| Window and layout | `CPWindow`, `CPView` | Main shell, subviews, and geometry |
| Form controls | `CPTextField`, `CPButton` | Input and actions |
| Navigation | `CPTabView` | Primary app tabs and detail tabs |
| Structured data | `CPTableView` | Main data presentation (Account, record, PLC tables) |
| Text output | `CPTextView` | JSON fallback panes and read-only debug output |

### Delegates and Data Sources

Cappuccino leans heavily on Cocoa's delegation model. For example, `CPTableView` requires a datasource to provide data:

```objectivec
[_accountsTable setDelegate:self];
[_accountsTable setDataSource:self];

// Required datasource methods:
- (int)numberOfRowsInTableView:(CPTableView)aTableView { return [_data count]; }
- (id)tableView:(CPTableView)aTableView objectValueForTableColumn:(CPTableColumn)aColumn row:(int)aRow { ... }
```

### Summary

When working with Objective-J in Garazyk:
- If it starts with `CP`, it's a Cappuccino class; use message sends.
- If it uses `var`, `function`, `===`, `[]`, or `{}`, you're in JavaScript territory.
- Update ivars first, then call a refresh or reload method (like `reloadData`).
- Guard for both `nil` and `undefined` when dealing with network data.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `[obj someMethod:] is not a function` | Message send to a raw JS object or `undefined` | Check if `obj` is a Cappuccino object; ensure it's not `nil`/`undefined` |
| `CPInvalidArgumentException` | Calling a method that doesn't exist | Check selector name and colon count (e.g., `doThing` vs `doThing:`) |
| UI doesn't update | Forgot to call `reloadData` or `setNeedsDisplay:YES` | Controllers must explicitly trigger view refreshes after state changes |

## Next Steps

1. Move to [Tutorial 7b: The Admin UI Architecture](./tutorial-7b-admin-ui) to see how these concepts are applied to the PDS management interface.
2. Read the official [Cappuccino Documentation](https://www.cappuccino.dev/learn/documentation/) for deep dives into specific classes.

## Summary

Objective-J provides the structure needed for a large-scale UI while preserving the flexibility of the browser runtime. By mastering the message-send syntax and the delegate/datasource pattern, you can extend the Garazyk UI with confidence.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
