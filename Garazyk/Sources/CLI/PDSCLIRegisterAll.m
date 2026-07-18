// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCLIRegisterAll.m

 @abstract Explicit CLI command registration for non-Apple platforms.

 @discussion On Linux/GNUstep with GNU ld, +load methods in unreferenced
 objects within static archives are silently stripped. This file provides
 an explicit registration function called from main() to ensure all CLI
 commands are available regardless of linker behavior.

 On Apple platforms, +load fires reliably from static libraries, so this
 function is a harmless no-op (commands are already registered).
 */

#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"

@interface PDSCLIServeCommand : PDSBaseCommand @end
@interface PDSCLIHealthCommand : PDSBaseCommand @end
@interface PDSCLIAdminCommand : PDSBaseCommand @end
@interface PDSCLINukeCommand : PDSBaseCommand @end
@interface PDSCLIAccountCommand : PDSBaseCommand @end
@interface PDSCLIRepoCommand : PDSBaseCommand @end
@interface PDSCLIDaemonCommand : PDSBaseCommand @end
@interface PDSCLIOAuthCommand : PDSBaseCommand @end
@interface PDSCLIInitCommand : PDSBaseCommand @end
@interface PDSCLIInviteCommand : PDSBaseCommand @end

void PDSCLIRegisterAllCommandsForDispatcher(PDSCLIDispatcher *dispatcher) {
    if (!dispatcher) return;

    NSArray<Class> *commandClasses = @[
        [PDSCLIServeCommand class],
        [PDSCLIHealthCommand class],
        [PDSCLIAdminCommand class],
        [PDSCLINukeCommand class],
        [PDSCLIAccountCommand class],
        [PDSCLIRepoCommand class],
        [PDSCLIDaemonCommand class],
        [PDSCLIOAuthCommand class],
        [PDSCLIInitCommand class],
        [PDSCLIInviteCommand class]
    ];

    for (Class cmdClass in commandClasses) {
        if (cmdClass) {
            id cmd = [[cmdClass alloc] init];
            if (cmd) {
                [dispatcher addCommand:cmd];
            }
        }
    }
}

void PDSCLIRegisterAllCommands(void) {
    PDSCLIRegisterAllCommandsForDispatcher([PDSCLIDispatcher sharedDispatcher]);
}
