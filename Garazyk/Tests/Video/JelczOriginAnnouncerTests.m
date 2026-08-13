// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/GZJelczOriginAnnouncer.h"

@interface GZJelczOriginAnnounceHTTPStub : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *script;
@property (nonatomic, assign) NSUInteger scriptIndex;
@end

@implementation GZJelczOriginAnnounceHTTPStub
- (instancetype)init {
    self = [super init];
    if (self) {
        _requests = [NSMutableArray array];
    }
    return self;
}
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    [self.requests addObject:request];
    NSDictionary *step = nil;
    if (self.scriptIndex < self.script.count) {
        step = self.script[self.scriptIndex++];
    }
    NSInteger status = step[@"status"] ? [step[@"status"] integerValue] : 200;
    NSData *body = step[@"body"];
    if (!body && [step[@"json"] isKindOfClass:[NSDictionary class]]) {
        body = [NSJSONSerialization dataWithJSONObject:step[@"json"] options:0 error:nil];
    }
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:status
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{@"Content-Type": @"application/json"}];
    }
    if (status >= 400) {
        if (error && !body) {
            *error = [NSError errorWithDomain:@"stub" code:status userInfo:nil];
        }
        return body;
    }
    return body ?: [NSData data];
}
@end

@interface JelczOriginAnnouncerTests : XCTestCase
@end

@implementation JelczOriginAnnouncerTests

- (void)testOriginRecordIncludesOptionalTicketFields {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSDictionary *rec =
        [GZJelczOriginAnnouncer originRecordWithSubjectURI:@"at://did:plc:author/tools.garazyk.video/abc"
                                                subjectCID:@"bafySubject"
                                                 serverDID:@"did:web:jelcz.example"
                                              watchBaseURL:@"https://jelcz.example"
                                               manifestCID:@"bafyManifest"
                                                 httpsBase:@"https://cdn.example"
                                                irohTicket:@"ticket123"
                                                       now:now];
    XCTAssertEqualObjects(rec[@"$type"], @"tools.garazyk.video.origin");
    XCTAssertEqualObjects(rec[@"server"], @"did:web:jelcz.example");
    XCTAssertEqualObjects(rec[@"httpsBase"], @"https://cdn.example");
    XCTAssertEqualObjects(rec[@"irohTicket"], @"ticket123");
    XCTAssertEqualObjects(rec[@"subject"][@"uri"], @"at://did:plc:author/tools.garazyk.video/abc");
    XCTAssertTrue([rec[@"createdAt"] isKindOfClass:[NSString class]]);
    XCTAssertEqualObjects(rec[@"createdAt"], rec[@"lastSeenAt"]);
}

- (void)testPublishCreateSessionThenPutRecord {
    GZJelczOriginAnnounceHTTPStub *stub = [[GZJelczOriginAnnounceHTTPStub alloc] init];
    stub.script = @[
        @{
            @"status": @200,
            @"json": @{
                @"accessJwt": @"tok-abc",
                @"did": @"did:plc:broadcaster",
            },
        },
        @{
            @"status": @200,
            @"json": @{
                @"uri": @"at://did:plc:broadcaster/tools.garazyk.video.origin/r1",
                @"cid": @"bafyOrigin",
            },
        },
    ];
    GZJelczOriginAnnouncer *ann =
        [[GZJelczOriginAnnouncer alloc] initWithHTTPClient:stub
                                                pdsBaseURL:@"https://pds.example/"
                                                identifier:@"broadcaster.example"
                                               appPassword:@"app-pass"
                                                 serverDID:@"did:web:jelcz.example"];
    NSDictionary *record =
        [GZJelczOriginAnnouncer originRecordWithSubjectURI:@"at://did:plc:author/tools.garazyk.video/x"
                                                subjectCID:@"bafyS"
                                                 serverDID:@"did:web:jelcz.example"
                                              watchBaseURL:@"https://jelcz.example"
                                               manifestCID:@"bafyM"
                                                 httpsBase:nil
                                                irohTicket:nil
                                                       now:[NSDate date]];
    NSError *error = nil;
    NSDictionary *out = [ann publishOriginRecord:record rkey:@"r1" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(out[@"uri"], @"at://did:plc:broadcaster/tools.garazyk.video.origin/r1");
    XCTAssertEqualObjects(out[@"cid"], @"bafyOrigin");
    XCTAssertEqualObjects(out[@"rkey"], @"r1");
    XCTAssertEqual(stub.requests.count, (NSUInteger)2);
    XCTAssertTrue([stub.requests[0].URL.path containsString:@"com.atproto.server.createSession"]);
    XCTAssertTrue([stub.requests[1].URL.path containsString:@"com.atproto.repo.putRecord"]);
    NSString *auth = stub.requests[1].allHTTPHeaderFields[@"Authorization"];
    XCTAssertEqualObjects(auth, @"Bearer tok-abc");
    id putBody = [NSJSONSerialization JSONObjectWithData:stub.requests[1].HTTPBody options:0 error:nil];
    XCTAssertEqualObjects(putBody[@"collection"], @"tools.garazyk.video.origin");
    XCTAssertEqualObjects(putBody[@"repo"], @"did:plc:broadcaster");
    XCTAssertEqualObjects(putBody[@"rkey"], @"r1");
}

- (void)testRetractDeletesRecord {
    GZJelczOriginAnnounceHTTPStub *stub = [[GZJelczOriginAnnounceHTTPStub alloc] init];
    stub.script = @[
        @{
            @"status": @200,
            @"json": @{@"accessJwt": @"tok", @"did": @"did:plc:b"},
        },
        @{@"status": @200, @"json": @{}},
    ];
    GZJelczOriginAnnouncer *ann =
        [[GZJelczOriginAnnouncer alloc] initWithHTTPClient:stub
                                                pdsBaseURL:@"http://127.0.0.1:2583"
                                                identifier:@"user"
                                               appPassword:@"pw"
                                                 serverDID:@"did:web:s"];
    NSError *error = nil;
    XCTAssertTrue([ann retractOriginWithRkey:@"tid1" error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(stub.requests.count, (NSUInteger)2);
    XCTAssertTrue([stub.requests[1].URL.path containsString:@"com.atproto.repo.deleteRecord"]);
}

- (void)testPublishFailsWithoutCredentials {
    GZJelczOriginAnnounceHTTPStub *stub = [[GZJelczOriginAnnounceHTTPStub alloc] init];
    GZJelczOriginAnnouncer *ann =
        [[GZJelczOriginAnnouncer alloc] initWithHTTPClient:stub
                                                pdsBaseURL:@"http://pds"
                                                identifier:@""
                                               appPassword:@""
                                                 serverDID:@"did:web:s"];
    NSError *error = nil;
    NSDictionary *out = [ann publishOriginRecord:@{} rkey:@"x" error:&error];
    XCTAssertNil(out);
    XCTAssertEqual(error.code, GZJelczOriginAnnouncerErrorInvalidArgument);
    XCTAssertEqual(stub.requests.count, (NSUInteger)0);
}

@end
