#import <Foundation/Foundation.h>

@class Firehose;
@class FirehoseSubscription;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const FirehoseErrorDomain;
extern NSInteger const FirehoseErrorCodeSubscriptionFailed;
extern NSInteger const FirehoseErrorCodeEventEncodingFailed;
extern NSInteger const FirehoseErrorCodeSubscriptionClosed;

typedef NS_ENUM(NSInteger, FirehoseEventKind) {
    FirehoseEventKindCommit,
    FirehoseEventKindIdentity,
    FirehoseEventKindError
};

@interface FirehoseCommitEvent : NSObject

@property (nonatomic, copy) NSString *repo;
@property (nonatomic, copy) NSString *commit;
@property (nonatomic, copy, nullable) NSString *previous;
@property (nonatomic, strong) NSArray<NSDictionary *> *ops;
@property (nonatomic, copy, nullable) NSArray<NSString *> *blobs;

+ (instancetype)eventWithRepo:(NSString *)repo commit:(NSString *)commit ops:(NSArray<NSDictionary *> *)ops;

@end

@interface FirehoseIdentityEvent : NSObject

@property (nonatomic, copy) NSString *did;

+ (instancetype)eventWithDid:(NSString *)did;

@end

@interface FirehoseErrorEvent : NSObject

@property (nonatomic, copy) NSString *message;

+ (instancetype)eventWithMessage:(NSString *)message;

@end

@protocol FirehoseSubscriptionDelegate <NSObject>
@optional
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveIdentityEvent:(FirehoseIdentityEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveErrorEvent:(FirehoseErrorEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didCloseWithError:(nullable NSError *)error;
- (void)firehoseSubscriptionDidConnect:(FirehoseSubscription *)subscription;
@end

@interface FirehoseSubscription : NSObject

@property (nonatomic, weak, nullable) id<FirehoseSubscriptionDelegate> delegate;
@property (nonatomic, copy, nullable) NSString *cursor;
@property (nonatomic, copy, nullable) NSArray<NSString *> *collections;
@property (nonatomic, readonly) BOOL isActive;

- (instancetype)initWithCursor:(nullable NSString *)cursor collections:(nullable NSArray<NSString *> *)collections;
- (void)cancel;

@end

@interface Firehose : NSObject

@property (nonatomic, weak, nullable) id<FirehoseSubscriptionDelegate> delegate;
@property (nonatomic, readonly) NSURL *serverURL;
@property (nonatomic, readonly) BOOL isConnected;

- (instancetype)initWithServerURL:(NSURL *)serverURL;
- (FirehoseSubscription *)subscribeWithCursor:(nullable NSString *)cursor
                                   collections:(nullable NSArray<NSString *> *)collections
                                     delegate:(nullable id<FirehoseSubscriptionDelegate>)delegate;
- (void)connect;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
