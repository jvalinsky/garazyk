// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @file PDSCLIDefinitions.h
 * @brief Core definitions for the ATProto PDS command-line interface.
 *
 * This file defines the protocols, classes, and constants used to implement
 * the PDS CLI system. It provides a framework for registering commands,
 * dispatching them with arguments, and managing command execution context.
 */

typedef NS_ENUM(NSInteger, PDSCLIExitCode) {
    PDSCLIExitCodeSuccess = 0,
    PDSCLIExitCodeGeneralError = 1,
    PDSCLIExitCodeInvalidArguments = 2,
    PDSCLIExitCodeNotFound = 3,
    PDSCLIExitCodeUnauthorized = 4,
    PDSCLIExitCodeDatabaseError = 5,
    PDSCLIExitCodeNetworkError = 6
};

@class PDSCLICommandContext;

/**
 * @protocol PDSCLICommand
 * @brief Protocol defining the interface for all PDS CLI commands.
 *
 * Any command that can be executed through the PDS CLI must conform to this
 * protocol. The protocol defines the metadata properties needed for command
 * registration and help output, as well as the execution method.
 */
@protocol PDSCLICommand <NSObject>

/**
 * @brief The primary name of the command.
 *
 * This is the canonical identifier used to invoke the command.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 * @brief A brief one-line summary of the command's purpose.
 */
@property (nonatomic, copy, readonly) NSString *summary;

/**
 * @brief A usage string showing how to invoke the command.
 *
 * Should follow the pattern: "command [options] <args>"
 */
@property (nonatomic, copy, readonly) NSString *usage;

/**
 * @brief Detailed help text for the command.
 *
 * May be nil if no additional help is provided.
 */
@property (nonatomic, copy, readonly, nullable) NSString *helpText;

/**
 * @brief Returns the list of aliases for this command.
 *
 * Aliases are alternative names that can be used to invoke the command.
 *
 * @return An array of alias strings, or an empty array if none exist.
 */
- (NSArray<NSString *> *)aliases;

/**
 * @brief Executes the command with the given arguments.
 *
 * @param args    The command-line arguments passed to this command.
 * @param context The execution context containing configuration and services.
 */
- (int)executeWithArguments:(NSArray<NSString *> *)args
                    context:(PDSCLICommandContext *)context;

@optional
/**
 * @brief Returns the list of subcommand names supported by this command.
 *
 * @return An array of subcommand names, or nil if no subcommands exist.
 */
- (NSArray<NSString *> *)subcommands;

/**
 * @brief Returns the subcommand with the specified name.
 *
 * @param name The name of the subcommand to retrieve.
 * @return The subcommand instance, or nil if not found.
 */
- (id<PDSCLICommand>)subcommandForName:(NSString *)name;

@end

/**
 * @class PDSBaseCommand
 * @brief A base class providing common functionality for CLI commands.
 *
 * PDSBaseCommand implements default behaviors for command metadata and
 * alias management. Subclasses should override the required properties
 * and the executeWithArguments:context: method.
 */
@interface PDSBaseCommand : NSObject <PDSCLICommand>

/**
 * @brief Creates and returns a new command instance.
 *
 * @return A new PDSBaseCommand instance.
 */
+ (instancetype)command;

/**
 * @brief Returns the list of aliases for this command.
 *
 * The default implementation returns an empty array.
 *
 * @return An array of alias strings.
 */
- (NSArray<NSString *> *)aliases;

@end

/**
 * @class PDSCLICommandContext
 * @brief Encapsulates the execution context for CLI commands.
 *
 * This class provides access to configuration, services, and output utilities
 * for commands during execution. It manages the data directory, configuration
 * path, verbosity settings, and output formatting.
 */
@interface PDSCLICommandContext : NSObject

/**
 * @brief The directory containing PDS data files.
 *
 * Defaults to a platform-appropriate location if not explicitly set.
 */
@property (nonatomic, copy) NSString *dataDir;

/**
 * @brief Path to the configuration file.
 *
 * If nil, default configuration locations are searched.
 */
@property (nonatomic, copy) NSString *configPath;

/**
 * @brief Whether verbose output is enabled.
 *
 * When YES, commands should produce additional diagnostic information.
 */
@property (nonatomic, assign) BOOL verbose;

/**
 * @brief Whether to output in JSON format.
 *
 * When YES, informational output should be formatted as JSON.
 */
@property (nonatomic, assign) BOOL jsonOutput;

/**
 * @brief The admin password for authenticated operations.
 *
 * May be nil if not provided via command-line arguments.
 */
@property (nonatomic, copy, nullable) NSString *adminPassword;

/**
 * @brief Initializes a new command context with default values.
 *
 * @return A newly initialized PDSCLICommandContext.
 */
- (instancetype)init;

/**
 * @brief Loads and returns the configuration from the config file.
 *
 * @return A dictionary containing configuration key-value pairs.
 */
- (NSDictionary *)loadConfig;

/**
 * @brief Returns a database connection object for data operations.
 *
 * @return An object representing the database connection.
 */
- (id)databaseConnection;

/**
 * @brief Prints an error message to the appropriate output stream.
 *
 * @param error The error message to display.
 */
- (void)printError:(NSString *)error;

/**
 * @brief Prints informational output.
 *
 * @param info The information message to display.
 */
- (void)printInfo:(NSString *)info;

/**
 * @brief Prints an object as JSON output.
 *
 * @param The object to serialize and print as JSON.
 */
- (void)printJSON:(id)object;

@end

/**
 * @class PDSCLIDispatcher
 * @brief Manages command registration and execution dispatching.
 *
 * The dispatcher maintains a registry of available commands and routes
 * incoming command invocations to the appropriate handler. It also
 * provides functionality for displaying usage information and help.
 */
@interface PDSCLIDispatcher : NSObject

/**
 * @brief Returns the shared singleton dispatcher instance.
 *
 * @return The shared PDSCLIDispatcher instance.
 */
+ (instancetype)sharedDispatcher;

/**
 * @brief Registers a command with the dispatcher.
 *
 * @param command The command to register.
 */
- (void)addCommand:(id<PDSCLICommand>)command;

/**
 * @brief Removes a command from the dispatcher by name.
 *
 * @param name The name of the command to remove.
 */
- (void)removeCommandWithName:(NSString *)name;

/**
 * @brief Dispatches a command with the given name and arguments.
 *
 * @param commandName The name of the command to execute.
 * @param args        The arguments to pass to the command.
 * @param context     The execution context.
 */
- (int)dispatchWithCommandName:(NSString *)commandName
                        arguments:(NSArray<NSString *> *)args
                         context:(PDSCLICommandContext *)context;

/**
 * @brief Returns the command instance for the given name or alias.
 *
 * @param name The command name or alias.
 * @return The command instance, or nil if not found.
 */
- (nullable id<PDSCLICommand>)commandForName:(NSString *)name;

/**
 * @brief Prints usage information for all registered commands.
 */
- (void)printUsage;

/**
 * @brief Prints detailed usage information for a specific command.
 *
 * @param command The command for which to display usage.
 */
- (void)printUsageForCommand:(id<PDSCLICommand>)command;

@end

NS_ASSUME_NONNULL_END
