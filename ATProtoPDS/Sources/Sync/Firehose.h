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
 */
@interface FirehoseCommitEvent : NSObject

/*! The DID of the repository. */
@property (nonatomic, copy) NSString *repo;

/*! The commit CID. */
@property (nonatomic, copy) NSString *commit;

/*! The previous commit CID (for chain verification). */
@property (nonatomic, copy, nullable) NSString *previous;

/*! Array of record operations in the commit. */
@property (nonatomic, strong) NSArray<NSDictionary *> *ops;

/*! CIDs of blobs referenced in the commit. */
@property (nonatomic, copy, nullable) NSArray<NSString *> *blobs;

+ (instancetype)eventWithRepo:(NSString *)repo commit:(NSString *)commit ops:(NSArray<NSDictionary *> *)ops;

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

/*! The error message. */
@property (nonatomic, copy) NSString *message;

+ (instancetype)eventWithMessage:(NSString *)message;

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
@property (nonatomic, copy, nullable, readonly) NSString *cursor;

/*! Collections to filter events for. */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *collections;

/*! Whether the subscription is currently active. */
@property (nonatomic, readonly) BOOL isActive;

- (instancetype)initWithCursor:(nullable NSString *)cursor collections:(nullable NSArray<NSString *> *)collections;
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
- (FirehoseSubscription *)subscribeWithCursor:(nullable NSString *)cursor
                                   collections:(nullable NSArray<NSString *> *)collections
                                     delegate:(nullable id<FirehoseSubscriptionDelegate>)delegate;
/*! Connects to the Firehose server. */
- (void)connect;

/*! Disconnects from the server. */
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
