#import "NodeInfoProvider.h"
#import "App/PDSConfiguration.h"
#import "NodeInfoSchemas.h"

@implementation NodeInfoProvider {
    NSString *_baseURL;
    PDSConfiguration *_configuration;
    NSDictionary *_nodeInfo20;
    NSDictionary *_nodeInfo21;
    NSDictionary *_discoveryDocument20;
    NSDictionary *_discoveryDocument21;
}

- (nullable instancetype)initWithBaseURL:(NSString *)baseURL
                          configuration:(PDSConfiguration *)configuration {
    if (!baseURL || [baseURL length] == 0) {
        return nil;
    }

    if (!configuration) {
        return nil;
    }

    if (![baseURL hasPrefix:@"https://"] && ![baseURL hasPrefix:@"http://"]) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:baseURL];
    if (!url || !url.host || [url.host length] == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _baseURL = [baseURL copy];
        _configuration = configuration;
        _totalUsers = 0;
        _activeUsersMonth = 0;
        _activeUsersHalfyear = 0;
        _localPosts = 0;
        _localComments = 0;

        [self buildDocuments];
    }
    return self;
}

- (void)buildDocuments {
    NSURL *baseUrl = [NSURL URLWithString:_baseURL];
    NSString *schema20URL = [[baseUrl URLByAppendingPathComponent:@"nodeinfo/2.0"] absoluteString];
    NSString *schema21URL = [[baseUrl URLByAppendingPathComponent:@"nodeinfo/2.1"] absoluteString];

    NSDictionary *software20 = @{
        @"name": _configuration.nodeinfoSoftwareName ?: @"atprotopds",
        @"version": _configuration.nodeinfoSoftwareVersion ?: @"1.0.0"
    };

    if (_configuration.nodeinfoRepositoryURL) {
        NSMutableDictionary *mutableSoftware20 = [software20 mutableCopy];
        mutableSoftware20[@"repository"] = _configuration.nodeinfoRepositoryURL;
        software20 = [mutableSoftware20 copy];
    }

    if (_configuration.nodeinfoHomepageURL) {
        NSMutableDictionary *mutableSoftware20 = [software20 mutableCopy];
        mutableSoftware20[@"homepage"] = _configuration.nodeinfoHomepageURL;
        software20 = [mutableSoftware20 copy];
    }

    NSDictionary *usage = @{
        @"users": @{
            @"total": @(_totalUsers),
            @"activeHalfyear": @(_activeUsersHalfyear),
            @"activeMonth": @(_activeUsersMonth)
        },
        @"localPosts": @(_localPosts),
        @"localComments": @(_localComments)
    };

    NSDictionary *services = @{
        @"inbound": @[],
        @"outbound": @[]
    };

    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"supportedLexicons"] = @[
        @"com.atproto.*",
        @"app.bsky.*"
    ];
    metadata[@"plcUrl"] = _configuration.plcURL ?: @"https://plc.directory";

    _nodeInfo20 = @{
        @"version": NodeInfoVersion20,
        @"software": software20,
        @"protocols": @[NodeInfoProtocolAtproto],
        @"services": services,
        @"openRegistrations": @(_configuration.nodeinfoOpenRegistrations),
        @"usage": usage,
        @"metadata": metadata
    };

    _nodeInfo21 = @{
        @"version": NodeInfoVersion21,
        @"software": software20,
        @"protocols": @[NodeInfoProtocolAtproto],
        @"services": services,
        @"openRegistrations": @(_configuration.nodeinfoOpenRegistrations),
        @"usage": usage,
        @"metadata": metadata
    };

    _discoveryDocument20 = @{
        @"links": @[
            @{
                @"rel": NodeInfoSchemaRel20,
                @"href": schema20URL
            }
        ]
    };

    _discoveryDocument21 = @{
        @"links": @[
            @{
                @"rel": NodeInfoSchemaRel21,
                @"href": schema21URL
            }
        ]
    };
}

- (void)refreshUsageStatistics {
    [self buildDocuments];
}

@end
