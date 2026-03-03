#import <Foundation/Foundation.h>

@interface FirehoseCommitEvent : NSObject
@property (nonatomic, assign) NSUInteger seq;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, strong) NSData *commit;
@property (nonatomic, copy) NSString *rev;
@property (nonatomic, copy, nullable) NSString *since;
@property (nonatomic, strong) NSData *blocks;
@property (nonatomic, strong) NSArray<NSDictionary *> *ops;
@property (nonatomic, strong) NSArray *blobs;
@property (nonatomic, copy) NSString *time;
@end

@interface EventFormatter : NSObject

- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error;

@end
