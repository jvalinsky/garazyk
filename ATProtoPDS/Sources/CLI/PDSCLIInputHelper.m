#import "PDSCLIInputHelper.h"
#import <termios.h>
#import <unistd.h>
#import <stdio.h>
#import <string.h>

@implementation PDSCLIInputHelper

+ (BOOL)isInteractiveTTY {
    return isatty(STDIN_FILENO);
}

+ (nullable NSString *)promptForInput:(NSString *)prompt defaultValue:(nullable NSString *)defaultValue {
    if (![self isInteractiveTTY]) {
        return defaultValue;
    }

    if (defaultValue) {
        printf("%s [%s]: ", [prompt UTF8String], [defaultValue UTF8String]);
    } else {
        printf("%s: ", [prompt UTF8String]);
    }
    fflush(stdout);

    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return nil;
    }

    NSString *input = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (input.length == 0 && defaultValue) {
        return defaultValue;
    }
    return input;
}

+ (nullable NSString *)promptForPassword:(NSString *)prompt {
    if (![self isInteractiveTTY]) {
        return nil;
    }

    printf("%s: ", [prompt UTF8String]);
    fflush(stdout);

    struct termios oldt, newt;
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);

    char buffer[1024];
    char *result = fgets(buffer, sizeof(buffer), stdin);

    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    printf("\n");

    if (result == NULL) {
        return nil;
    }

    return [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

+ (nullable NSString *)promptForPasswordWithConfirmation:(NSString *)prompt
                                            confirmPrompt:(NSString *)confirmPrompt
                                                minLength:(NSUInteger)minLength
                                              maxAttempts:(NSUInteger)maxAttempts {
    for (NSUInteger attempt = 0; attempt < maxAttempts; attempt++) {
        NSString *password = [self promptForPassword:prompt];
        if (!password) return nil;

        if (password.length < minLength) {
            printf("Password must be at least %lu characters long. Try again.\n", (unsigned long)minLength);
            continue;
        }

        NSString *confirm = [self promptForPassword:confirmPrompt];
        if (!confirm) return nil;

        if ([password isEqualToString:confirm]) {
            return password;
        } else {
            printf("Passwords do not match. Try again.\n");
        }
    }

    printf("Too many failed attempts. Aborting.\n");
    return nil;
}

+ (BOOL)promptForConfirmation:(NSString *)prompt defaultYes:(BOOL)defaultYes {
    if (![self isInteractiveTTY]) {
        return defaultYes;
    }

    NSString *options = defaultYes ? @"[Y/n]" : @"[y/N]";
    NSString *input = [self promptForInput:[NSString stringWithFormat:@"%@ %@", prompt, options] defaultValue:nil];

    if (!input || input.length == 0) {
        return defaultYes;
    }

    NSString *lowerInput = [input lowercaseString];
    if ([lowerInput hasPrefix:@"y"]) return YES;
    if ([lowerInput hasPrefix:@"n"]) return NO;

    return defaultYes;
}

+ (NSInteger)promptForChoice:(NSString *)prompt choices:(NSArray<NSString *> *)choices defaultIndex:(NSInteger)defaultIndex {
    if (![self isInteractiveTTY]) {
        return defaultIndex;
    }

    printf("%s\n", [prompt UTF8String]);
    for (NSUInteger i = 0; i < choices.count; i++) {
        printf("  %lu) %s\n", (unsigned long)i + 1, [choices[i] UTF8String]);
    }

    NSString *promptStr = [NSString stringWithFormat:@"Choice (1-%lu)", (unsigned long)choices.count];
    NSString *defaultValueStr = [NSString stringWithFormat:@"%lu", (unsigned long)defaultIndex + 1];
    
    while (YES) {
        NSString *input = [self promptForInput:promptStr defaultValue:defaultValueStr];
        if (!input) return defaultIndex;

        NSInteger choice = [input integerValue];
        if (choice >= 1 && choice <= choices.count) {
            return choice - 1;
        }
        printf("Invalid choice. Please enter a number between 1 and %lu.\n", (unsigned long)choices.count);
    }
}

@end
