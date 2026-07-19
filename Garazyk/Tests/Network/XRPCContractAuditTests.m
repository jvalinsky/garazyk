// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Characterization / contract tests for registered XRPC handlers (P0 gap — refactor audit P0#1).
// For each known NSID: assert the HTTP verb matches the Lexicon type (query→GET, procedure→POST),
// the NSID is well-formed, and auth-required endpoints reject unauthenticated calls with 401.
// The verb-contract tests are expected to FAIL until HTTP method enforcement is added to the
// dispatcher or individual handlers — that failure is the intended signal.
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

// ---------------------------------------------------------------------------
// Lexicon catalog: NSID → @"query" (GET) or @"procedure" (POST).
// Expand this table as the registry catalog is built out per refactor audit P0#1.
// ---------------------------------------------------------------------------
static NSDictionary<NSString *, NSString *> *XRPCKnownLexiconTypes(void) {
    return @{
        // com.atproto.server
        @"com.atproto.server.describeServer"        : @"query",
        @"com.atproto.server.createSession"         : @"procedure",
        @"com.atproto.server.getSession"            : @"query",
        @"com.atproto.server.refreshSession"        : @"procedure",
        @"com.atproto.server.deleteSession"         : @"procedure",
        @"com.atproto.server.createAccount"         : @"procedure",
        @"com.atproto.server.deleteAccount"         : @"procedure",
        @"com.atproto.server.createInviteCode"      : @"procedure",
        @"com.atproto.server.createInviteCodes"     : @"procedure",
        @"com.atproto.server.getAccountInviteCodes" : @"query",
        // com.atproto.repo
        @"com.atproto.repo.createRecord"            : @"procedure",
        @"com.atproto.repo.putRecord"               : @"procedure",
        @"com.atproto.repo.deleteRecord"            : @"procedure",
        @"com.atproto.repo.getRecord"               : @"query",
        @"com.atproto.repo.listRecords"             : @"query",
        @"com.atproto.repo.describeRepo"            : @"query",
        @"com.atproto.repo.uploadBlob"              : @"procedure",
        @"com.atproto.repo.applyWrites"             : @"procedure",
        // com.atproto.identity
        @"com.atproto.identity.resolveHandle"       : @"query",
        @"com.atproto.identity.updateHandle"        : @"procedure",
        // com.atproto.sync
        @"com.atproto.sync.getRepo"                 : @"query",
        @"com.atproto.sync.getLatestCommit"         : @"query",
        @"com.atproto.sync.listRepos"               : @"query",
        // com.atproto.admin
        @"com.atproto.admin.getSubjectStatus"       : @"query",
        @"com.atproto.admin.updateSubjectStatus"    : @"procedure",
    };
}

// Build a minimal HttpRequest for dispatching to the XRPC dispatcher in tests.
static HttpRequest *xrpcAuditRequest(NSString *method, NSString *nsid) {
    HttpMethod httpMethod = [method isEqualToString:@"GET"] ? HttpMethodGET : HttpMethodPOST;
    NSString *path = [NSString stringWithFormat:@"/xrpc/%@", nsid];
    return [[HttpRequest alloc] initWithMethod:httpMethod
                                  methodString:method
                                          path:path
                                   queryString:@""
                                   queryParams:@{}
                                       version:@"1.1"
                                       headers:@{}
                                          body:[NSData data]
                                  remoteAddress:@"127.0.0.1"];
}

@interface XRPCContractAuditTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@end

@implementation XRPCContractAuditTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                                withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.application = [[PDSApplication alloc] initWithDataDirectory:self.tempDir];
    // Use a fresh dispatcher (not the shared singleton) so tests are independent.
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher
                                          application:self.application];
}

- (void)tearDown {
    self.dispatcher  = nil;
    [self.application stop];
    self.application = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

// MARK: - Verb contract: query methods must reject POST with 405

- (void)testQueryMethodsRespondToGETNotPOST {
    // ATProto Lexicon: query type → GET only. Any POST to a query NSID must return 405.
    // NOTE: This test is expected to FAIL until HTTP method enforcement is added to
    // XrpcDispatcher.handleRequest:response: or individual handler blocks (refactor P0#1).
    NSDictionary *lexicon = XRPCKnownLexiconTypes();
    NSUInteger failCount = 0;
    for (NSString *nsid in lexicon) {
        if (![lexicon[nsid] isEqualToString:@"query"]) continue;
        HttpRequest *req = xrpcAuditRequest(@"POST", nsid);
        HttpResponse *resp = [HttpResponse response];
        [self.dispatcher handleRequest:req response:resp];
        if (resp.statusCode != 405) {
            NSLog(@"[contract] POST to query NSID '%@' returned %ld (expected 405)",
                  nsid, (long)resp.statusCode);
            failCount++;
        }
    }
    XCTAssertEqual(failCount, 0U,
        @"%lu query NSIDs did not return 405 for POST. "
        @"Add HTTP method enforcement per refactor audit P0#1.", (unsigned long)failCount);
}

// MARK: - Verb contract: procedure methods must reject GET with 405

- (void)testProcedureMethodsRespondToPOSTNotGET {
    // ATProto Lexicon: procedure type → POST only. Any GET to a procedure NSID must return 405.
    // NOTE: Also expected to fail until enforcement is added.
    NSDictionary *lexicon = XRPCKnownLexiconTypes();
    NSUInteger failCount = 0;
    for (NSString *nsid in lexicon) {
        if (![lexicon[nsid] isEqualToString:@"procedure"]) continue;
        HttpRequest *req = xrpcAuditRequest(@"GET", nsid);
        HttpResponse *resp = [HttpResponse response];
        [self.dispatcher handleRequest:req response:resp];
        if (resp.statusCode != 405) {
            NSLog(@"[contract] GET to procedure NSID '%@' returned %ld (expected 405)",
                  nsid, (long)resp.statusCode);
            failCount++;
        }
    }
    XCTAssertEqual(failCount, 0U,
        @"%lu procedure NSIDs did not return 405 for GET.", (unsigned long)failCount);
}

// MARK: - Auth contract: auth-required endpoints must return 401 without a token

- (void)testAuthRequiredMethodsReject401WithNoToken {
    // These NSIDs require a valid Authorization header. An unauthenticated request (no header)
    // must return 401, not 200 or 500.
    NSArray<NSString *> *authRequired = @[
        @"com.atproto.repo.createRecord",
        @"com.atproto.repo.putRecord",
        @"com.atproto.repo.deleteRecord",
        @"com.atproto.server.getSession",
        @"com.atproto.server.deleteSession",
        @"com.atproto.server.createInviteCode",
    ];
    NSDictionary *lexicon = XRPCKnownLexiconTypes();
    NSUInteger failCount = 0;
    for (NSString *nsid in authRequired) {
        NSString *verb = [lexicon[nsid] isEqualToString:@"query"] ? @"GET" : @"POST";
        HttpRequest *req = xrpcAuditRequest(verb, nsid);
        HttpResponse *resp = [HttpResponse response];
        [self.dispatcher handleRequest:req response:resp];
        if (resp.statusCode != 401) {
            NSLog(@"[contract] %@ %@ returned %ld without auth (expected 401)",
                  verb, nsid, (long)resp.statusCode);
            failCount++;
        }
    }
    XCTAssertEqual(failCount, 0U,
        @"%lu auth-required NSIDs did not return 401 for unauthenticated requests.",
        (unsigned long)failCount);
}

// MARK: - NSID validity: all registered NSIDs must match ATProto NSID syntax

- (void)testAllRegisteredNSIDsAreWellFormed {
    // Access the private methodHandlers dict via KVC to enumerate all registered NSIDs.
    // ATProto NSID syntax: two or more dot-separated segments, each [a-zA-Z][a-zA-Z0-9-]*.
    NSDictionary<NSString *, id> *handlers = [self.dispatcher valueForKey:@"methodHandlers"];
    XCTAssertNotNil(handlers, @"methodHandlers must be accessible via KVC");

    NSError *regexError = nil;
    NSRegularExpression *nsidRegex = [NSRegularExpression
        regularExpressionWithPattern:
            @"^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z][a-zA-Z0-9-]*){2,}$"
        options:0
        error:&regexError];
    XCTAssertNil(regexError);

    NSUInteger badCount = 0;
    for (NSString *nsid in handlers.allKeys) {
        NSUInteger matches = [nsidRegex numberOfMatchesInString:nsid
                                                        options:0
                                                          range:NSMakeRange(0, nsid.length)];
        if (matches == 0) {
            NSLog(@"[contract] Malformed NSID: '%@'", nsid);
            badCount++;
        }
    }
    XCTAssertEqual(badCount, 0U,
        @"%lu registered NSIDs have invalid ATProto NSID syntax.", (unsigned long)badCount);
}

// MARK: - Coverage completeness: all catalog NSIDs must be registered

- (void)testAllKnownCatalogNSIDsAreRegistered {
    // For each NSID in the catalog, dispatch a correctly-verbed request and assert the response
    // is not 404/501 (which would indicate the NSID has no registered handler).
    NSDictionary *lexicon = XRPCKnownLexiconTypes();
    NSUInteger missingCount = 0;
    for (NSString *nsid in lexicon) {
        NSString *verb = [lexicon[nsid] isEqualToString:@"query"] ? @"GET" : @"POST";
        HttpRequest *req = xrpcAuditRequest(verb, nsid);
        HttpResponse *resp = [HttpResponse response];
        [self.dispatcher handleRequest:req response:resp];
        if (resp.statusCode == 404 || resp.statusCode == 501) {
            NSLog(@"[contract] NSID not registered: %@ %@ → %ld",
                  verb, nsid, (long)resp.statusCode);
            missingCount++;
        }
    }
    XCTAssertEqual(missingCount, 0U,
        @"%lu catalog NSIDs returned 404/501 — not registered in XrpcMethodRegistry.",
        (unsigned long)missingCount);
}

@end
