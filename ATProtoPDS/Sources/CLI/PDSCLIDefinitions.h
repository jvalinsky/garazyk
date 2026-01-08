#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSCLIDefinitions.h
 
 @abstract Command-line interface definitions for the PDS.
 
 @discussion This header defines the CLI framework including command
 protocols, context, and dispatcher for the pds command-line tool.
 
 @copyright Copyright (c) 2024 Jack Myers
 */

/*!
 @enum PDSCLIExitCode
 
 @abstract Exit codes for the CLI tool.
 
 @constant PDSCLIExitCodeSuccess Command succeeded.
 @constant PDSCLIExitCodeGeneralError A general error occurred.
 @constant PDSCLIExitCodeInvalidArguments Invalid command arguments.
 @constant PDSCLIExitCodeNotFound The requested resource was not found.
 @constant PDSCLIExitCodeUnauthorized Authentication failed.
 @constant PDSCLIExitCodeDatabaseError A database error occurred.
 @constant PDSCLIExitCodeNetworkError A network error occurred.
 */
typedef NS_ENUM(NSInteger, PDSCLIExitCode) {
    PDSCLIExitCodeSuccess = 0,
    PDSCLIExitCodeDatabaseError = 5,
    PDSCLIExitCodeGeneralError = 1,
    PDSCLIExitCodeInvalidArguments = 2,
    PDSCLIExitCodeNetworkError = 6,
    PDSCLIExitCodeNotFound = 3,
    PDSCLIExitCodeUnauthorized = 4
};

@class PDSCLICommandContext;

/*!
 @protocol PDSCLICommand
 
 @abstract Protocol for CLI commands.
 
 @discussion Commands implement this protocol to provide their name,
 usage, and execution logic. Commands can have optional subcommands
 for nested functionality.
 */
@protocol PDSCLICommand <NSObject>

/*! The command name. */
@property (nonatomic, copy, readonly) NSString *name;

/*! A brief summary of what the command does. */
@property (nonatomic, copy, readonly) NSString *summary;

/*! Usage string showing command syntax. */
@property (nonatomic, copy, readonly) NSString *usage;

/*! Detailed help text (optional). */
@property (nonatomic, copy, readonly, nullable) NSString *helpText;

/*!
 @method aliases
 
 @abstract Returns command aliases.
 
 @return An array of alternative names for this command.
 */
- (NSArray<NSString *> *)aliases;

/*!
 @method executeWithArguments:context:
 
 @abstract Executes the command.
 
 @param args The command-line arguments.
 @param context The execution context with configuration.
 */
- (void)executeWithArguments:(NSArray<NSString *> *)args
                     context:(PDSCLICommandContext *)context;

@optional

/*! List of subcommand names (if this command supports subcommands). */
- (NSArray<NSString *> *)subcommands;

/*!
 @method subcommandForName:
 
 @abstract Returns a subcommand by name.
 
 @param name The subcommand name.
 @return The subcommand, or nil if not found.
 */
- (id<PDSCLICommand>)subcommandForName:(NSString *)name;

@end

/*!
 @class PDSBaseCommand
 
 @abstract Base class for CLI commands.
 
 @discussion PDSBaseCommand provides default implementations for
 command metadata. Subclasses should override the execute method.
 */
@interface PDSBaseCommand : NSObject <PDSCLICommand>

/*!
 @method command
 
 @abstract Creates a new command instance.
 
 @return A new command instance.
 */
+ (instancetype)command;

/*!
 @method aliases
 
 @abstract Returns empty array of aliases.
 
 @return Empty array.
 */
- (NSArray<NSString *> *)aliases;

@end

/*!
 @class PDSCLICommandContext
 
 @abstract Context for CLI command execution.
 
 @discussion PDSCLICommandContext provides access to configuration,
 database connections, and output methods for commands.
 */
@interface PDSCLICommandContext : NSObject

/*! Path to the PDS data directory. */
@property (nonatomic, copy) NSString *dataDir;

/*! Path to the configuration file. */
@property (nonatomic, copy) NSString *configPath;

/*! If YES, enable verbose output. */
@property (nonatomic, assign) BOOL verbose;

/*! If YES, output in JSON format. */
@property (nonatomic, assign) BOOL jsonOutput;

/*! Admin password for authenticated operations. */
@property (nonatomic, copy, nullable) NSString *adminPassword;

/*!
 @method init
 
 @abstract Initializes with default values.
 
 @return An initialized context.
 */
- (instancetype)init;

/*!
 @method loadConfig
 
 @abstract Loads configuration from the config file.
 
 @return The configuration dictionary.
 */
- (NSDictionary *)loadConfig;

/*!
 @method databaseConnection
 
 @abstract Returns a database connection.
 
 @return A database connection object.
 */
- (id)databaseConnection;

/*!
 @method printError:
 
 @abstract Prints an error message.
 
 @param error The error message to print.
 */
- (void)printError:(NSString *)error;

/*!
 @method printInfo:
 
 @abstract Prints an info message.
 
 @param info The info message to print.
 */
- (void)printInfo:(NSString *)info;

/*!
 @method printJSON:
 
 @abstract Prints an object as JSON.
 
 @param object The object to serialize and print.
 */
- (void)printJSON:(id)object;

@end

/*!
 @class PDSCLIDispatcher
 
 @abstract Routes CLI commands to handlers.
 
 @discussion PDSCLIDispatcher manages registered commands and routes
 incoming command invocations to the appropriate handler.
 */
@interface PDSCLIDispatcher : NSObject

/*!
 @method sharedDispatcher
 
 @abstract Returns the shared dispatcher.
 
 @return The singleton dispatcher.
 */
+ (instancetype)sharedDispatcher;

/*!
 @method addCommand:
 
 @abstract Registers a command with the dispatcher.
 
 @param command The command to register.
 */
- (void)addCommand:(id<PDSCLICommand>)command;

/*!
 @method removeCommandWithName:
 
 @abstract Removes a registered command.
 
 @param name The name of the command to remove.
 */
- (void)removeCommandWithName:(NSString *)name;

/*!
 @method dispatchWithCommandName:arguments:context:
 
 @abstract Dispatches a command invocation.
 
 @param commandName The name of the command to execute.
 @param args The command arguments.
 @param context The execution context.
 */
- (void)dispatchWithCommandName:(NSString *)commandName
                       arguments:(NSArray<NSString *> *)args
                        context:(PDSCLICommandContext *)context;

/*!
 @method printUsage
 
 @abstract Prints usage information for all commands.
 */
- (void)printUsage;

/*!
 @method printUsageForCommand:
 
 @abstract Prints usage for a specific command.
 
 @param command The command to show usage for.
 */
- (void)printUsageForCommand:(id<PDSCLICommand>)command;

@end

NS_ASSUME_NONNULL_END
