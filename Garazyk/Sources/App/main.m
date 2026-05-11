// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @abstract Application entry point for macOS ATProto PDS.

 @discussion Launches the NSApplication and sets up the application delegate.
 The delegate handles initialization of the PDS server and lifecycle management.
 This is the entry point for the GUI application.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}