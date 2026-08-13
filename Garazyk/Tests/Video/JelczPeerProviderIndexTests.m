// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczPeerProviderIndex.h"

@interface JelczPeerProviderIndexTests : XCTestCase
@end

@implementation JelczPeerProviderIndexTests

- (void)testConsentDeniesWhenAllowlistsEmpty {
    XCTAssertFalse([GZJelczPeerProviderIndex allowsStreamer:@"did:plc:a"
                                                 broadcaster:@"did:web:x"
                                            allowedStreamers:[NSSet set]
                                         allowedBroadcasters:[NSSet set]]);
}

- (void)testConsentAllowsStarStreamer {
    NSSet *s = [GZJelczPeerProviderIndex allowlistSetFromCSV:@"*"];
    XCTAssertTrue([GZJelczPeerProviderIndex allowsStreamer:@"did:plc:anyone"
                                               broadcaster:nil
                                          allowedStreamers:s
                                       allowedBroadcasters:[NSSet set]]);
}

- (void)testConsentMatchesBroadcaster {
    NSSet *b = [GZJelczPeerProviderIndex allowlistSetFromCSV:@"did:web:ok"];
    XCTAssertTrue([GZJelczPeerProviderIndex allowsStreamer:nil
                                               broadcaster:@"did:web:ok"
                                          allowedStreamers:[NSSet set]
                                       allowedBroadcasters:b]);
    XCTAssertFalse([GZJelczPeerProviderIndex allowsStreamer:nil
                                                broadcaster:@"did:web:no"
                                           allowedStreamers:[NSSet set]
                                        allowedBroadcasters:b]);
}

- (void)testBroadcastOriginParsesTicketAndWebsocketHTTPS {
    NSDictionary *rec = @{
        @"$type": @"place.stream.broadcast.origin",
        @"streamer": @"did:plc:streamer",
        @"server": @"did:web:node.example",
        @"broadcaster": @"did:web:ops",
        @"updatedAt": @"2026-08-12T12:00:00Z",
        @"irohTicket": @"ticket123",
        @"websocketURL": @"wss://node.example/live",
    };
    GZJelczPeerProviderEntry *e =
        [GZJelczPeerProviderIndex entryFromBroadcastOriginRecord:rec];
    XCTAssertEqualObjects(e.httpsBase, @"https://node.example");
    XCTAssertEqualObjects(e.irohTicket, @"ticket123");
    XCTAssertEqualObjects(e.source, @"broadcast.origin");
    XCTAssertNotNil(e.updatedAt);
}

- (void)testGarazykVideoOriginUsesWatchBase {
    NSDictionary *rec = @{
        @"$type": @"tools.garazyk.video.origin",
        @"server": @"did:web:jelcz.local",
        @"watchBaseUrl": @"http://127.0.0.1:2586/",
        @"manifestCid": @"bafyreibaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        @"lastSeenAt": @"2026-08-12T18:00:00Z",
        @"createdAt": @"2026-08-12T17:00:00Z",
        @"subject": @{@"uri": @"at://did:plc:x/tools.garazyk.video/1", @"cid": @"bafy"},
    };
    GZJelczPeerProviderEntry *e =
        [GZJelczPeerProviderIndex entryFromGarazykVideoOriginRecord:rec];
    XCTAssertEqualObjects(e.httpsBase, @"http://127.0.0.1:2586");
    XCTAssertEqualObjects(e.source, @"video.origin");
}

- (void)testRankPrefersFresherUpdatedAt {
    GZJelczPeerProviderEntry *old = [[GZJelczPeerProviderEntry alloc] init];
    old.httpsBase = @"https://old.example";
    old.updatedAt = [NSDate dateWithTimeIntervalSince1970:1000];
    old.source = @"broadcast.origin";
    GZJelczPeerProviderEntry *neu = [[GZJelczPeerProviderEntry alloc] init];
    neu.httpsBase = @"https://new.example";
    neu.updatedAt = [NSDate dateWithTimeIntervalSince1970:2000];
    neu.source = @"broadcast.origin";
    NSArray *ranked = [GZJelczPeerProviderIndex rankEntries:@[ old, neu ]];
    XCTAssertEqualObjects([ranked[0] httpsBase], @"https://new.example");
}

- (void)testHTTPSBasesBootstrapThenEnvThenConsentedOrigins {
    GZJelczPeerProviderEntry *blocked = [[GZJelczPeerProviderEntry alloc] init];
    blocked.httpsBase = @"https://blocked.example";
    blocked.streamerDID = @"did:plc:no";
    blocked.source = @"broadcast.origin";
    blocked.updatedAt = [NSDate date];

    GZJelczPeerProviderEntry *ok = [[GZJelczPeerProviderEntry alloc] init];
    ok.httpsBase = @"https://ok.example";
    ok.streamerDID = @"did:plc:yes";
    ok.source = @"broadcast.origin";
    ok.updatedAt = [NSDate dateWithTimeIntervalSinceNow:-10];

    NSArray *bases =
        [GZJelczPeerProviderIndex httpsProviderBasesWithBootstrap:@"https://stream.place"
                                                     envPeerBases:@[ @"http://127.0.0.1:2587" ]
                                                    originEntries:@[ blocked, ok ]
                                                 allowedStreamers:[NSSet setWithObject:@"did:plc:yes"]
                                              allowedBroadcasters:[NSSet set]];
    XCTAssertEqualObjects(bases, (@[
        @"https://stream.place",
        @"http://127.0.0.1:2587",
        @"https://ok.example",
    ]));
}

- (void)testEmptyAllowlistDropsBroadcastOriginsKeepsBootstrap {
    GZJelczPeerProviderEntry *ok = [[GZJelczPeerProviderEntry alloc] init];
    ok.httpsBase = @"https://ok.example";
    ok.streamerDID = @"did:plc:yes";
    ok.source = @"broadcast.origin";
    NSArray *bases =
        [GZJelczPeerProviderIndex httpsProviderBasesWithBootstrap:@"https://stream.place"
                                                     envPeerBases:nil
                                                    originEntries:@[ ok ]
                                                 allowedStreamers:[NSSet set]
                                              allowedBroadcasters:[NSSet set]];
    XCTAssertEqualObjects(bases, (@[ @"https://stream.place" ]));
}

- (void)testEntriesFromOriginsJSONArray {
    NSArray *json = @[
        @{
            @"$type": @"place.stream.broadcast.origin",
            @"streamer": @"did:plc:s",
            @"server": @"did:web:n",
            @"updatedAt": @"2026-08-01T00:00:00Z",
            @"websocketURL": @"https://n.example/",
        },
    ];
    NSArray *entries =
        [GZJelczPeerProviderIndex entriesFromOriginsJSONObject:json configuredBaseURL:nil];
    XCTAssertEqual(entries.count, 1u);
    XCTAssertEqualObjects([entries[0] httpsBase], @"https://n.example");
}

@end
