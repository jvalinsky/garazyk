// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCLIInputHelper.h

 @abstract Interactive terminal input helpers for CLI commands.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSCLIInputHelper

 @abstract Provides prompt and selection helpers for interactive CLI flows.
 */
@interface PDSCLIInputHelper : NSObject

/*!
 @method isInteractiveTTY

 @abstract Returns whether stdin is attached to an interactive terminal.
 */
+ (BOOL)isInteractiveTTY;

/*!
 @method promptForInput:defaultValue:

 @abstract Prompts for a line of text, with optional default.

 @param prompt Prompt label shown to the user.
 @param defaultValue Default returned when user submits an empty line.
 @result User input, default value, or nil if read fails.
 */
+ (nullable NSString *)promptForInput:(NSString *)prompt defaultValue:(nullable NSString *)defaultValue;

/*!
 @method promptForPassword:

 @abstract Prompts for hidden password input.

 @param prompt Prompt label shown to the user.
 @result Entered password, or nil if input is unavailable.
 */
+ (nullable NSString *)promptForPassword:(NSString *)prompt;

/*!
 @method promptForPasswordWithConfirmation:confirmPrompt:minLength:maxAttempts:

 @abstract Prompts for password entry with confirmation and retry bounds.

 @param prompt Primary password prompt.
 @param confirmPrompt Confirmation prompt.
 @param minLength Minimum accepted password length.
 @param maxAttempts Maximum attempts before aborting.
 @result Confirmed password, or nil when validation fails repeatedly.
 */
/**
 * @abstract Performs the promptForPasswordWithConfirmation operation.
 */
+ (nullable NSString *)promptForPasswordWithConfirmation:(NSString *)prompt
                                            confirmPrompt:(NSString *)confirmPrompt
                                                minLength:(NSUInteger)minLength
                                              maxAttempts:(NSUInteger)maxAttempts;

/*!
 @method promptForConfirmation:defaultYes:

 @abstract Prompts for a yes/no confirmation.

 @param prompt Prompt label shown to the user.
 @param defaultYes Default answer when user presses Enter.
 @result YES when confirmed, otherwise NO.
 */
+ (BOOL)promptForConfirmation:(NSString *)prompt defaultYes:(BOOL)defaultYes;

/*!
 @method promptForChoice:choices:defaultIndex:

 @abstract Prompts user to select one choice from a numbered list.

 @param prompt Prompt label shown above the choices.
 @param choices Ordered list of selectable options.
 @param defaultIndex Zero-based default index used for non-interactive mode or empty input.
 @result Zero-based selected index.
 */
+ (NSInteger)promptForChoice:(NSString *)prompt choices:(NSArray<NSString *> *)choices defaultIndex:(NSInteger)defaultIndex;

@end

NS_ASSUME_NONNULL_END
