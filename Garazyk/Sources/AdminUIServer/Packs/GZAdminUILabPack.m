// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUILabPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UIServiceConfig.h"

@implementation GZAdminUILabPack

+ (NSString *)packIdentifier {
    return @"lab";
}

+ (NSString *)displayName {
    return @"Lab";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    // The Lab owns its dedicated OAuth shell and does not contribute a shared-shell panel.
    return @[];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerLabRoutes];
}

+ (NSString *)labShellHTMLWithNonce:(NSString *)nonce configuration:(UIServiceConfig *)configuration {
    NSString *pdsBaseURL = [configuration.pdsBaseURL absoluteString];
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         configuration.host, (unsigned long)configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            configuration.host, (unsigned long)configuration.port];

    return [NSString stringWithFormat:
    @"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    @"<title>Garazyk Lab - AT Protocol</title>"
    @"<link rel=\"stylesheet\" href=\"/css/system.css\">"
    @"<link rel=\"stylesheet\" href=\"/css/components.css\">"
    @"<meta name=\"lab-pds-url\" content=\"%@\">"
    @"<meta name=\"lab-client-id\" content=\"%@\">"
    @"<meta name=\"lab-redirect-uri\" content=\"%@\">"
    @"<style nonce=\"%@\">"
    @".lab-shell { max-width: 800px; margin: 0 auto; padding: var(--space-lg); }"
    @".lab-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: var(--space-xl); padding-bottom: var(--space-lg); border-bottom: 1px solid var(--separator-color); }"
    @".lab-header h1 { margin: 0; }"
    @".lab-header a { color: var(--color-text-primary); text-decoration: none; font-size: var(--font-size-sm); }"
    @".lab-section { display: none; }"
    @".lab-section.active { display: block; }"
    @".login-form { margin-top: var(--space-lg); }"
    @".login-form .form-group { margin-bottom: var(--space-md); }"
    @".account-card { background: var(--color-bg-secondary); border: 1px solid var(--separator-color); border-radius: var(--radius-md); padding: var(--space-lg); margin-bottom: var(--space-lg); }"
    @".account-row { display: flex; justify-content: space-between; padding: var(--space-sm) 0; border-bottom: 1px solid var(--separator-color-secondary); }"
    @".account-row:last-child { border-bottom: none; }"
    @".account-label { font-weight: 500; color: var(--color-text-secondary); }"
    @".account-value { font-family: monospace; font-size: var(--font-size-sm); }"
    @".handle-update-form { margin-top: var(--space-lg); padding-top: var(--space-lg); border-top: 1px solid var(--separator-color); }"
    @".handle-update-form .form-group { margin-bottom: var(--space-md); }"
    @"</style>"
    @"</head><body class=\"lab-shell\">"
    @"<header class=\"lab-header\">"
    @"<h1>Garazyk Lab</h1>"
    @"<a href=\"/admin\">← Back to Admin</a>"
    @"</header>"
    @"<main>"
    @"<section class=\"lab-section active\" id=\"lab-login-section\">"
    @"<h2>Sign in with AT Protocol</h2>"
    @"<p class=\"text-secondary\">Enter your handle or DID to sign in to your account.</p>"
    @"<form class=\"login-form\" data-lab-form=\"start-oauth\">"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-handle-input\">Handle or DID</label>"
    @"<input type=\"text\" id=\"lab-handle-input\" class=\"form-input\" placeholder=\"alice.example.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary\">Sign In with AT Protocol</button>"
    @"</form>"
    @"</section>"
    @"<section class=\"lab-section\" id=\"lab-account-section\">"
    @"<div class=\"account-card\">"
    @"<h2>Your Account</h2>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">DID</span>"
    @"<span class=\"account-value\" id=\"lab-did-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Handle</span>"
    @"<span class=\"account-value\" id=\"lab-handle-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Email</span>"
    @"<span class=\"account-value\" id=\"lab-email-display\">—</span>"
    @"</div>"
    @"</div>"
    @"<form class=\"handle-update-form\" data-lab-form=\"update-handle\">"
    @"<h3>Update Handle</h3>"
    @"<p class=\"text-secondary text-sm\">Change your handle to a new one.</p>"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-new-handle-input\">New Handle</label>"
    @"<input type=\"text\" id=\"lab-new-handle-input\" class=\"form-input\" placeholder=\"newhandle.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Update Handle</button>"
    @"<div id=\"lab-update-result\" aria-live=\"polite\"></div>"
    @"</form>"
    @"<div style=\"margin-top:var(--space-xl);padding-top:var(--space-lg);border-top:1px solid var(--separator-color);\">"
    @"<button data-lab-action=\"sign-out\" class=\"btn btn-secondary btn-sm\">Sign Out</button>"
    @"</div>"
    @"</section>"
    @"</main>"
    @"<script src=\"/js/lab.js\"></script>"
    @"</body></html>",
    UIEscaped(pdsBaseURL), UIEscaped(clientId), UIEscaped(redirectUri), nonce];
}

+ (NSString *)labClientMetadataJSONWithConfiguration:(UIServiceConfig *)configuration {
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         configuration.host, (unsigned long)configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            configuration.host, (unsigned long)configuration.port];

    NSDictionary *metadata = @{
        @"client_id": clientId,
        @"client_name": @"Garazyk Admin Lab",
        @"redirect_uris": @[redirectUri],
        @"scope": @"atproto transition:generic",
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web",
        @"dpop_bound_access_tokens": @YES
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

@end
