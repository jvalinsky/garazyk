/*!
 @file PDSInstallerCommand.h

 @abstract CLI command declarations for install/uninstall and launchctl service management.

 @discussion Declares the command classes used by the `pds install` command tree.
 */

#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSInstallerCommand

 @abstract Top-level command for install-related operations.

 @discussion Parses install flags and dispatches to service subcommands when requested.
 */
@interface PDSInstallerCommand : PDSBaseCommand
@end

/*!
 @class PDSUninstallerCommand

 @abstract Command that removes LaunchDaemon and/or LaunchAgent installation.
 */
@interface PDSUninstallerCommand : PDSBaseCommand
@end

/*!
 @class PDSServiceCommand

 @abstract Command that controls the running PDS service process.
 */
@interface PDSServiceCommand : PDSBaseCommand
@end

/*!
 @class PDSServiceStatusCommand

 @abstract Command that reports current launch service installation/runtime status.
 */
@interface PDSServiceStatusCommand : PDSBaseCommand
@end

NS_ASSUME_NONNULL_END
