#import "ChatModerationService.h"

@interface ChatModerationService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@end

@implementation ChatModerationService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getActorMetadata:(NSString *)actor
                                      error:(NSError **)error {
    NSString *sql = @"SELECT * FROM chat_actor_metadata WHERE did = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[actor] error:error];
    
    if (!results) {
        return nil;
    }
    
    if (results.count == 0) {
        return @{
            @"did": actor,
            @"muted": @NO,
            @"blocked": @NO,
            @"labels": @[]
        };
    }
    
    NSDictionary *row = results.firstObject;
    NSMutableDictionary *metadata = [row mutableCopy];
    
    // Parse labels if present
    NSString *labelsJson = row[@"labels"];
    if (labelsJson && ![labelsJson isKindOfClass:[NSNull class]]) {
        NSData *data = [labelsJson dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *labels = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        metadata[@"labels"] = labels ?: @[];
    } else {
        metadata[@"labels"] = @[];
    }
    
    metadata[@"muted"] = @([row[@"muted"] boolValue]);
    metadata[@"blocked"] = @([row[@"blocked"] boolValue]);
    
    return metadata;
}

- (nullable NSDictionary *)getMessageContext:(NSString *)messageId
                                       error:(NSError **)error {
    // Basic implementation: find the message and its conversation
    NSString *sql = @"SELECT * FROM messages WHERE id = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[messageId] error:error];
    
    if (!results || results.count == 0) {
        return nil;
    }
    
    NSDictionary *message = results.firstObject;
    NSString *convoId = message[@"convo_id"];
    
    // Get surrounding messages (simplified: just get last 5 messages in convo)
    NSString *contextSql = @"SELECT * FROM messages WHERE convo_id = ? ORDER BY created_at DESC LIMIT 5";
    NSArray *contextMessages = [self.database executeParameterizedQuery:contextSql params:@[convoId] error:error];
    
    return @{
        @"message": message,
        @"context": contextMessages ?: @[]
    };
}

- (BOOL)updateActorAccess:(NSString *)actor
                   access:(NSDictionary *)access
                    error:(NSError **)error {
    NSNumber *muted = access[@"muted"];
    NSNumber *blocked = access[@"blocked"];
    NSArray *labels = access[@"labels"];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    NSString *labelsJson = @"[]";
    if (labels) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:labels options:0 error:nil];
        labelsJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    NSString *sql = @"INSERT INTO chat_actor_metadata (did, muted, blocked, labels, updated_at) "
                    @"VALUES (?, ?, ?, ?, ?) "
                    @"ON CONFLICT(did) DO UPDATE SET "
                    @"muted = excluded.muted, "
                    @"blocked = excluded.blocked, "
                    @"labels = excluded.labels, "
                    @"updated_at = excluded.updated_at";
    
    NSArray *params = @[
        actor,
        muted ?: @0,
        blocked ?: @0,
        labelsJson,
        @( (long long)now )
    ];
    
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

@end
