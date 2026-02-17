/*!
 @file Firehose.h

 @abstract Real-time event streaming for ATProto repositories.

 @discussion Implements the ATProto Firehose protocol for subscribing to
 repository commits and identity updates. Provides WebSocket-based streaming
 with cursor-based replay support.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class Firehose;
@class FirehoseSubscription;
@class CID;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for Firehose operations. */
extern NSString * const FirehoseErrorDomain;

/*! Error code when subscription fails to connect. */
extern NSInteger const FirehoseErrorCodeSubscriptionFailed;

/*! Error code when event encoding fails. */
extern NSInteger const FirehoseErrorCodeEventEncodingFailed;

/*! Error code when subscription is closed unexpectedly. */
extern NSInteger const FirehoseErrorCodeSubscriptionClosed;

/*!
 @enum FirehoseEventKind

 @abstract Types of events streamed on the Firehose.

 @constant FirehoseEventKindCommit Repository commit event.
 @constant FirehoseEventKindIdentity Identity update event.
 @constant FirehoseEventKindError Error event.
 */
typedef NS_ENUM(NSInteger, FirehoseEventKind) {
    FirehoseEventKindCommit,
    FirehoseEventKindIdentity,
    FirehoseEventKindError
};

/*!
 @class FirehoseCommitEvent

 @abstract Represents a repository commit event.
 
 Per com.atproto.sync.subscribeRepos#commit lexicon.
 */
@interface FirehoseCommitEvent : NSObject

// Required fields

/*! The stream sequence number of this message. */
@property (nonatomic, assign) int64_t seq;

/*! DEPRECATED -- unused. Always false. */
@property (nonatomic, assign) BOOL rebase;

/*! DEPRECATED -- replaced by #sync event. Always false. */
@property (nonatomic, assign) BOOL tooBig;

/*! The repo this event comes from (DID). */
@property (nonatomic, copy) NSString *repo;

/*! Repo commit object CID. */
@property (nonatomic, strong) CID *commit;

/*! The rev of the emitted commit (TID). */
@property (nonatomic, copy) NSString *rev;

/*! The rev of the last emitted commit from this repo (nullable). */
@property (nonatomic, copy, nullable) NSString *since;

/*! CAR file containing relevant blocks as a diff. */
@property (nonatomic, strong) NSData *blocks;

/*! List of repo mutation operations in this commit. */
@property (nonatomic, strong) NSArray<NSDictionary *> *ops;

/*! DEPRECATED -- will soon always be empty. List of new blobs. */
@property (nonatomic, copy) NSArray<CID *> *blobs;

/*! Timestamp of when this message was originally broadcast (RFC-3339). */
@property (nonatomic, copy) NSString *time;

// Optional fields

/*! The root CID of the MST tree for the previous commit. */
@property (nonatomic, strong, nullable) CID *prevData;

+ (instancetype)eventWithRepo:(NSString *)repo commit:(CID *)commit ops:(NSArray<NSDictionary *> *)ops;

@end

/*!
 @class FirehoseIdentityEvent

 @abstract Represents an identity update event.
 */
@interface FirehoseIdentityEvent : NSObject

/*! The DID whose identity was updated. */
@property (nonatomic, copy) NSString *did;

/*! The new handle (may be nil if not changed). */
@property (nonatomic, copy, nullable) NSString *handle;

+ (instancetype)eventWithDid:(NSString *)did;

@end

/*!
 @class FirehoseAccountEvent

 @abstract Represents an account status event (takedown, suspension, etc).
 */
@interface FirehoseAccountEvent : NSObject

/*! The DID of the affected account. */
@property (nonatomic, copy) NSString *did;

/*! Whether the account is currently active. */
@property (nonatomic, assign) BOOL active;

/*! The account status (e.g., "takendown", "suspended", "deactivated"). */
@property (nonatomic, copy, nullable) NSString *status;

/*! Timestamp of the event in ISO 8601 format. */
@property (nonatomic, copy) NSString *time;

+ (instancetype)eventWithDid:(NSString *)did
                      active:(BOOL)active
                      status:(nullable NSString *)status;

@end

/*!
 @class FirehoseInfoEvent

 @abstract Represents an informational message on the stream.
 */
@interface FirehoseInfoEvent : NSObject

/*! The kind of info message (e.g., "OutdatedCursor", "HandshakeComplete"). */
@property (nonatomic, copy) NSString *kind;

/*! The message content. */
@property (nonatomic, copy) NSString *message;

+ (instancetype)eventWithKind:(NSString *)kind message:(NSString *)message;

@end

/*!
 @class FirehoseErrorEvent

 @abstract Represents an error event on the stream.
 */
@interface FirehoseErrorEvent : NSObject

/*! Machine-readable error code (for example, "FutureCursor"). */
@property (nonatomic, copy) NSString *error;

/*! Human-readable error message. */
@property (nonatomic, copy, nullable) NSString *message;

+ (instancetype)eventWithMessage:(NSString *)message;
+ (instancetype)eventWithError:(NSString *)error message:(nullable NSString *)message;

@end

/*!
 @protocol FirehoseSubscriptionDelegate

 @abstract Delegate for receiving Firehose events.
 */
@protocol FirehoseSubscriptionDelegate <NSObject>
@optional
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveIdentityEvent:(FirehoseIdentityEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveErrorEvent:(FirehoseErrorEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didCloseWithError:(nullable NSError *)error;
- (void)firehoseSubscriptionDidConnect:(FirehoseSubscription *)subscription;
@end

/*!
 @class FirehoseSubscription

 @abstract An active subscription to the Firehose.
 */
@interface FirehoseSubscription : NSObject

/*! The delegate receiving events. */
@property (nonatomic, weak, nullable, readonly) id<FirehoseSubscriptionDelegate> delegate;

/*! Cursor position for resuming the stream. */
@property (nonatomic, assign, readonly) int64_t cursor;

/*! Collections to filter events for. */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *collections;

/*! Whether the subscription is currently active. */
@property (nonatomic, readonly) BOOL isActive;

- (instancetype)initWithCursor:(int64_t)cursor collections:(nullable NSArray<NSString *> *)collections;
- (void)cancel;

@end

/*!
 @class Firehose

 @abstract Client for ATProto Firehose event streaming.
 */
@interface Firehose : NSObject

/*! Delegate for receiving events. */
@property (nonatomic, weak, nullable, readonly) id<FirehoseSubscriptionDelegate> delegate;

/*! URL of the Firehose server. */
@property (nonatomic, readonly) NSURL *serverURL;

/*! Whether currently connected to the server. */
@property (nonatomic, readonly) BOOL isConnected;

- (instancetype)initWithServerURL:(NSURL *)serverURL;

/*! Creates a new subscription with optional cursor and collection filter. */
- (FirehoseSubscription *)subscribeWithCursor:(int64_t)cursor
                                   collections:(nullable NSArray<NSString *> *)collections
                                     delegate:(nullable id<FirehoseSubscriptionDelegate>)delegate;
/*! Connects to the Firehose server. */
- (void)connect;

/*! Disconnects from the server. */
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
