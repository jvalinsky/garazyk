#import <Foundation/Foundation.h>
#import "WebSocketConnection.h"

@interface SubscribeReposHandler : NSObject

- (instancetype)init;

- (void)acceptConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor;
- (void)broadcastCommit:(NSString *)repo 
                    rev:(NSString *)rev
                 commit:(NSData *)commitCID
                 blocks:(NSData *)carBlocks
                    ops:(NSArray<NSDictionary *> *)ops;

@end
