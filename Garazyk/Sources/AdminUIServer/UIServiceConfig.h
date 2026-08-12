// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Stores endpoint and credential settings for the Admin UI service.
 */
@interface GZAdminUIServiceConfig : NSObject

@property(nonatomic, copy) NSString *host;
@property(nonatomic, assign) NSUInteger port;
@property(nonatomic, copy) NSString *adminPassword;
/** Service cookie namespace for embedded hosts; nil retains compatibility names. */
@property(nonatomic, copy, nullable) NSString *serviceIdentifier;

@property(nonatomic, strong) NSURL *pdsBaseURL;
@property(nonatomic, strong) NSURL *plcBaseURL;
/**
 * @abstract Base URL for the relay admin API.
 */
@property(nonatomic, strong) NSURL *relayBaseURL;
@property(nonatomic, strong) NSURL *appViewBaseURL;
@property(nonatomic, strong) NSURL *chatBaseURL;
@property(nonatomic, strong) NSURL *videoBaseURL;
@property(nonatomic, strong) NSURL *germBaseURL;

@property(nonatomic, copy, nullable) NSString *pdsAdminToken;
@property(nonatomic, copy, nullable) NSString *pdsAdminPassword;
@property(nonatomic, copy, nullable) NSString *plcAdminToken;
/**
 * @abstract Admin token used for relay requests.
 */
@property(nonatomic, copy, nullable) NSString *relayAdminToken;
@property(nonatomic, copy, nullable) NSString *appViewAdminToken;
@property(nonatomic, copy, nullable) NSString *chatAdminToken;
@property(nonatomic, copy, nullable) NSString *videoAdminToken;
@property(nonatomic, copy, nullable) NSString *germAdminToken;

/**
 * @abstract Directory containing static assets (CSS, JS, images). Defaults to Assets/ next to the binary.
 */
@property(nonatomic, copy, nullable) NSString *assetsDirectory;

/**
 * @abstract Configured peer admin UI links (displayName + url). Presentation only.
 * @discussion Populated from GARAZYK_ADMIN_UI_PEERS as comma-separated Name=URL
 *             entries. No health checks or credentials are attached.
 */
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *peerLinks;

+ (instancetype)configurationFromEnvironment;

/**
 * @abstract Update service URLs and tokens from the given dictionary.
 * @discussion Keys: pdsURL, plcURL, relayURL, appViewURL, chatURL, videoURL, germURL, pdsToken, plcToken, relayToken, appViewToken, chatToken, videoToken, germToken.
 * @param updates The dictionary of updates.
 * @return YES if all URLs were valid; otherwise NO.
 */
- (BOOL)updateWithDictionary:(NSDictionary<NSString *, NSString *> *)updates;

@end

NS_ASSUME_NONNULL_END
