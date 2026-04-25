// XrpcCorpusGenerator.m - Protocol-aware XRPC corpus generator
// Generates diverse XRPC inputs for fuzzing

#import <Foundation/Foundation.h>
#import "XRPC/XrpcTypes.h"
#import "XRPC/XrpcDispatcher.h"
#import "Lexicon/ATProtoLexiconResolver.h"

static const NSString *kKnownMethods[] = {
    @"com.atproto.server.createSession",
    @"com.atproto.server.refreshSession",
    @"com.atproto.server.getSession",
    @"com.atproto.server.deleteSession",
    @"com.atproto.server.createAccount",
    @"com.atproto.server.requestPasswordReset",
    @"com.atproto.server.resetPassword",
    @"com.atproto.server.activateAccount",
    @"com.atproto.server.requestEmailVerification",
    @"com.atproto.server.verifyEmail",
    @"com.atproto.server.requestAccountDelete",
    @"com.atproto.server.deleteAccount",
    @"com.atproto.server.listSessions",
    @"com.atproto.identity.signPlcOperation",
    @"com.atproto.identity.submitPlcOperation",
    @"com.atproto.identity.getRecommendedDidCredentials",
    @"com.atproto.identity.resolveHandle",
    @"com.atproto.identity.resolveByHandle",
    @"com.atproto.identity.updateHandle",
    @"com.atproto.repo.createRepo",
    @"com.atproto.repo.deleteRepo",
    @"com.atproto.repo.listRecords",
    @"com.atproto.repo.getRecord",
    @"com.atproto.repo.putRecord",
    @"com.atproto.repo.deleteRecord",
    @"com.atproto.repo.uploadBlob",
    @"com.atproto.repo.listBlobs",
    @"com.atproto.repo.describeRepo",
    @"com.atproto.repo.getLatestCommit",
    @"com.atproto.repo.listRepos",
    @"com.atproto.sync.getHead",
    @"com.atproto.sync.listBlobs",
    @"com.atproto.sync.getCommitPath",
    @"com.atproto.sync.requestCrawl",
    @"com.atproto.sync.notifyOfUpdate",
    @"app.bsky.actor.getProfile",
    @"app.bsky.actor.getProfiles",
    @"app.bsky.actor.searchActors",
    @"app.bsky.actor.searchActorsTypeahead",
    @"app.bsky.actor.getSuggestions",
    @"app.bsky.actor.getPreferences",
    @"app.bsky.actor.putPreferences",
    @"app.bsky.feed.getTimeline",
    @"app.bsky.feed.getPosts",
    @"app.bsky.feed.getPostThread",
    @"app.bsky.feed.getAuthorFeed",
    @"app.bsky.feed.getGlobalTimeline",
    @"app.bsky.feed.getListFeed",
    @"app.bsky.graph.getActors",
    @"app.bsky.graph.getFollows",
    @"app.bsky.graph.getFollowers",
    @"app.bsky.graph.getList",
    @"app.bsky.graph.getLists",
    @"app.bsky.graph.listBlocks",
    @"app.bsky.graph.createBlock",
    @"app.bsky.graph.deleteBlock",
    @"app.bsky.graph.createFollow",
    @"app.bsky.graph.deleteFollow",
    @"app.bsky.graph.createList",
    @"app.bsky.graph.list",
    @"app.bsky.graph.deleteList",
    @"app.bsky.graph.addRemoveFromList",
    @"app.bsky.graph.getListMutes",
    @"app.bsky.graph.listMutes",
    @"app.bsky.graph.muteActor",
    @"app.bsky.graph.unmuteActor",
    @"app.bsky.graph.muteThread",
    @"app.bsky.graph.unmuteThread",
    @"app.bsky.notification.listNotifications",
    @"app.bsky.notification.registerPush",
    @"app.bsky.notification.updateSeenAt",
    @"app.bsky.embed.record",
    @"app.bsky.feed.post",
    @"app.bsky.feed.repost",
    @"app.bsky.feed.like",
    @"app.bsky.feed.delete",
    @"app.bsky.feed.getLikes",
    @"app.bsky.graph.list StarterKit",
};

static NSArray<NSDictionary *> *generateSessionInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *createSession = @{
        @"identifier": @"test-handle.bsky.social",
        @"password": @"test-password-123"
    };
    [inputs addObject:createSession];
    
    NSDictionary *refresh = @{@"did": @"did:plc:abc123"};
    [inputs addObject:refresh];
    
    NSDictionary *deleteSession = @{@"did": @"did:plc:abc123"};
    [inputs addObject:deleteSession];
    
    NSDictionary *createAccount = @{
        @"handle": @"new-user.bsky.social",
        @"email": @"user@example.com",
        @"password": @"secure-pass-123",
        @"inviteCode": @"test-code"
    };
    [inputs addObject:createAccount];
    
    return inputs;
}

static NSArray<NSDictionary *> *generateRepoInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *getRecord = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"3k5c2l242v2c2"
    };
    [inputs addObject:getRecord];
    
    NSDictionary *listRecords = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.post",
        @"limit": @50,
        @"cursor": @""
    };
    [inputs addObject:listRecords];
    
    NSDictionary *putRecord = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"Test post content",
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:putRecord];
    
    NSDictionary *deleteRecord = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"3k5c2l242v2c2"
    };
    [inputs addObject:deleteRecord];
    
    return inputs;
}

static NSArray<NSDictionary *> *generateGraphInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *createFollow = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.graph.follow",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.graph.follow",
            @"subject": @{
                @"did": @"did:plc:target456",
                @"handle": @"target.bsky.social"
            },
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:createFollow];
    
    NSDictionary *createBlock = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.graph.block",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.graph.block",
            @"subject": @"did:plc:target456",
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:createBlock];
    
    NSDictionary *getProfile = @{
        @"actor": @"did:plc:abc123"
    };
    [inputs addObject:getProfile];
    
    NSDictionary *getProfiles = @{
        @"actors": @[@"did:plc:abc123", @"did:plc:def456"]
    };
    [inputs addObject:getProfiles];
    
    NSDictionary *getFollows = @{
        @"actor": @"did:plc:abc123",
        @"limit": @50
    };
    [inputs addObject:getFollows];
    
    NSDictionary *getFollowers = @{
        @"actor": @"did:plc:abc123",
        @"limit": @50
    };
    [inputs addObject:getFollowers];
    
    return inputs;
}

static NSArray<NSDictionary *> *generateFeedInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *createPost = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"Hello Bluesky!",
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:createPost];
    
    NSDictionary *createRepost = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.repost",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.feed.repost",
            @"subject": @"did:plc:target456/app.bsky.feed.post/3k5c2l242v2c2",
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:createRepost];
    
    NSDictionary *createLike = @{
        @"repo": @"did:plc:abc123",
        @"collection": @"app.bsky.feed.like",
        @"rkey": @"3k5c2l242v2c2",
        @"record": @{
            @"$type": @"app.bsky.feed.like",
            @"subject": @"did:plc:target456/app.bsky.feed.post/3k5c2l242v2c2",
            @"createdAt": @"2024-01-01T00:00:00Z"
        }
    };
    [inputs addObject:createLike];
    
    NSDictionary *getTimeline = @{
        @"limit": @50,
        @"cursor": @""
    };
    [inputs addObject:getTimeline];
    
    NSDictionary *getPosts = @{
        @"uris": @[
            @"did:plc:abc123/app.bsky.feed.post/3k5c2l242v2c2",
            @"did:plc:def456/app.bsky.feed.post/4abc3m453w3c3"
        ]
    };
    [inputs addObject:getPosts];
    
    NSDictionary *getPostThread = @{
        @"uri": @"did:plc:abc123/app.bsky.feed.post/3k5c2l242v2c2",
        @"depth": @5
    };
    [inputs addObject:getPostThread];
    
    return inputs;
}

static NSArray<NSDictionary *> *generateIdentityInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *resolveHandle = @{
        @"handle": @"user.bsky.social"
    };
    [inputs addObject:resolveHandle];
    
    NSDictionary *resolveByHandle = @{
        @"handle": @"user.bsky.social"
    };
    [inputs addObject:resolveByHandle];
    
    NSDictionary *updateHandle = @{
        @"handle": @"new-handle.bsky.social"
    };
    [inputs addObject:updateHandle];
    
    return inputs;
}

static NSArray<NSDictionary *> *generateSyncInputs(NSUInteger seed) {
    NSMutableArray *inputs = [NSMutableArray array];
    
    NSDictionary *getHead = @{
        @"did": @"did:plc:abc123"
    };
    [inputs addObject:getHead];
    
    NSDictionary *requestCrawl = @{
        @"hostname": @"pds.example.com"
    };
    [inputs addObject:requestCrawl];
    
    NSDictionary *listBlobs = @{
        @"did": @"did:plc:abc123",
        @"since": @"2024-01-01T00:00:00Z",
        @"limit": @50
    };
    [inputs addObject:listBlobs];
    
    return inputs;
}

static NSArray<NSData *> *generateXrpcCorpus(NSUInteger seed) {
    NSMutableArray *corpus = [NSMutableArray array];
    
    NSArray *(^generate)(NSUInteger) = ^NSArray *(NSUInteger type) {
        switch (type % 6) {
            case 0: return generateSessionInputs(seed);
            case 1: return generateRepoInputs(seed);
            case 2: return generateGraphInputs(seed);
            case 3: return generateFeedInputs(seed);
            case 4: return generateIdentityInputs(seed);
            case 5: return generateSyncInputs(seed);
            default: return @[];
        }
    };
    
    for (NSUInteger i = 0; i < 6; i++) {
        NSArray *inputs = generate(i);
        for (NSDictionary *input in inputs) {
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:input options:0 error:&error];
            if (json && !error) {
                [corpus addObject:json];
            }
        }
    }
    
    return corpus;
}

static NSArray<NSData *> *generateMinimalXrpcInputs(void) {
    NSMutableArray *corpus = [NSMutableArray array];
    
    NSArray *minimals = @[
        @{@"identifier": @"x", @"password": @"x"},
        @{@"did": @"did:plc:x"},
        @{@"repo": @"did:plc:x", @"collection": @"app.bsky.feed.post", @"rkey": @"x"},
        @{@"actor": @"did:plc:x"},
        @{@"uri": @"did:plc:x/app.bsky.feed.post/x"},
        @{@"hostname": @"x"},
        @{},
        @{@"limit": @1},
    ];
    
    for (NSDictionary *input in minimals) {
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:input options:0 error:&error];
        if (json && !error) {
            [corpus addObject:json];
        }
    }
    
    return corpus;
}

static NSArray<NSData *> *generateInvalidXrpcInputs(void) {
    NSMutableArray *corpus = [NSMutableArray array];
    
    NSArray *invalids = @[
        @[@"array"],
        @"just a string",
        @YES,
        @NO,
        @42,
        @{
            @"badCollection": @{
                @"$type": @123
            }
        },
        @{
            @"$type": @"invalid.type"
        },
        @{
            @"repo": @"invalid-did"
        },
        @{
            @"badCursor": [NSNull null]
        },
    ];
    
    for (id input in invalids) {
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:input options:0 error:&error];
        if (json && !error) {
            [corpus addObject:json];
        }
    }
    
    return corpus;
}