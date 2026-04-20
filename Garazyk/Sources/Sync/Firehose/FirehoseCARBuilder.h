#import <Foundation/Foundation.h>
#import "Core/CID.h"
#import "Repository/RepoCommit.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSData * _Nullable (^PDSBlockProvider)(NSData *cidBytes);
typedef NSArray<NSData *> * _Nullable (^PDSRevisionBlockListProvider)(NSString *rev);

@interface FirehoseCARBuilder : NSObject

+ (NSData *)buildCARForCommit:(RepoCommit *)commit
                          ops:(NSArray<NSDictionary *> *)ops
                blockProvider:(PDSBlockProvider)blockProvider
          revBlockListProvider:(nullable PDSRevisionBlockListProvider)revBlockListProvider;

+ (NSData *)buildCARForSyncCommitOnly:(RepoCommit *)commit;

@end

NS_ASSUME_NONNULL_END
