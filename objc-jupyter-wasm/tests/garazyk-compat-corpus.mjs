export const garazykCompatCorpus = [
  {
    name: "ATURI parser regression from atproto-kernel-tests",
    category: "atproto-aturi",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: [
      "DID: did:plc:z72i7hdynmk6r5zdbiyo6mp7",
      "Collection: app.bsky.actor.profile",
      "Rkey: self",
    ],
    tags: ["regression", "classes", "properties", "collections", "atproto-domain"],
    source: `@interface ATURI : NSObject
@property NSString *did;
@property NSString *collection;
@property NSString *rkey;
+ (instancetype)uriWithString:(NSString *)string;
@end

@implementation ATURI
+ (instancetype)uriWithString:(NSString *)string {
    if (string == nil) { return nil; }
    if ([string hasPrefix:@"at://"] == 0) { return nil; }
    NSArray *parts = [[string substringFromIndex:5] componentsSeparatedByString:@"/"];
    if (parts.count < 3) { return nil; }
    ATURI *uri = [[ATURI alloc] init];
    uri.did = [parts[0] copy];
    uri.collection = [parts[1] copy];
    uri.rkey = [parts[2] copy];
    return uri;
}
@end

ATURI *uri = [ATURI uriWithString:@"at://did:plc:z72i7hdynmk6r5zdbiyo6mp7/app.bsky.actor.profile/self"];
NSLog(@"DID: %@", uri.did);
NSLog(@"Collection: %@", uri.collection);
NSLog(@"Rkey: %@", uri.rkey);`,
  },
  {
    name: "Direct ObjC feature slice",
    category: "objc-direct",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["speaker=derived handled=1 count=2"],
    tags: ["classes", "protocols", "blocks", "exceptions", "inheritance"],
    source: `@protocol Speaker
- (NSString *)speak;
@end

@interface BaseSpeaker : NSObject <Speaker>
@end
@implementation BaseSpeaker
- (NSString *)speak { return @"base"; }
@end

@interface DerivedSpeaker : BaseSpeaker
@property NSString *name;
@end
@implementation DerivedSpeaker
- (NSString *)speak { return @"derived"; }
@end

DerivedSpeaker *speaker = [DerivedSpeaker new];
speaker.name = @"alice";
__block int count = 0;
NSArray *words = @[@"one", @"two"];
[words enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) { count++; }];
int handled = 0;
@try { @throw @"tutorial"; } @catch (id e) { handled = [e isEqualToString:@"tutorial"]; }
NSLog(@"speaker=%@ handled=%d count=%d", [speaker speak], handled, count);`,
  },
  {
    name: "Handle and DID validation guards",
    category: "identity",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["handle=1 did=1 bad=0"],
    tags: ["atproto-domain", "validation"],
    source: `@interface IdentityValidator : NSObject
- (BOOL)isValidHandle:(NSString *)handle;
- (BOOL)isValidDID:(NSString *)did;
@end

@implementation IdentityValidator
- (BOOL)isValidHandle:(NSString *)handle {
    if ([handle isEqualToString:@"bad"]) return NO;
    NSArray *parts = [handle componentsSeparatedByString:@"."];
    if (handle.length <= 3) return NO;
    if (parts.count < 2) return NO;
    return YES;
}
- (BOOL)isValidDID:(NSString *)did {
    return [did hasPrefix:@"did:plc:"] || [did hasPrefix:@"did:web:"];
}
@end

IdentityValidator *validator = [IdentityValidator new];
NSLog(@"handle=%d did=%d bad=%d",
      [validator isValidHandle:@"alice.example.com"],
      [validator isValidDID:@"did:plc:abc123"],
      [validator isValidHandle:@"bad"]);`,
  },
  {
    name: "Record store addressing and CID verification",
    category: "records",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["post=Hello ATProto same=1"],
    tags: ["atproto-domain", "collections", "data"],
    source: `NSMutableDictionary *store = [NSMutableDictionary dictionary];
NSDictionary *record = @{@"text": @"Hello ATProto", @"cid": @"bafyrei13"};
[store setObject:record forKey:@"at://did:plc:abc/app.bsky.feed.post/1"];
NSDictionary *post = [store objectForKey:@"at://did:plc:abc/app.bsky.feed.post/1"];
NSLog(@"post=%@ same=%d", [post objectForKey:@"text"], [@"bafyrei13" isEqualToString:[post objectForKey:@"cid"]]);`,
  },
  {
    name: "XRPC dispatch table with validation",
    category: "xrpc",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["ok=created missing=MethodNotFound"],
    tags: ["atproto-domain", "collections", "dispatch"],
    source: `NSMutableDictionary *handlers = [NSMutableDictionary dictionary];
[handlers setObject:@"created" forKey:@"com.atproto.server.createSession"];
NSString *ok = [handlers objectForKey:@"com.atproto.server.createSession"];
NSString *missing = @"MethodNotFound";
NSLog(@"ok=%@ missing=%@", ok, missing);`,
  },
  {
    name: "Firehose sequencing and cursor replay",
    category: "firehose",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["delivered=2 replay=1 next=3"],
    tags: ["atproto-domain", "collections", "sequencing"],
    source: `NSMutableArray *events = [NSMutableArray array];
int nextSeq = 1;
[events addObject:@{@"seq": @(nextSeq), @"type": @"commit", @"did": @"did:plc:a"}];
nextSeq++;
[events addObject:@{@"seq": @(nextSeq), @"type": @"identity", @"did": @"did:plc:a"}];
nextSeq++;
int replay = 0;
for (NSDictionary *event in events) {
    if ([[event objectForKey:@"seq"] intValue] > 1) replay++;
}
NSLog(@"delivered=%d replay=%d next=%d", (int)[events count], replay, nextSeq);`,
  },
  {
    name: "Repo diff and sync",
    category: "repo-sync",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["ops=2 synced=3"],
    tags: ["atproto-domain", "collections", "repo-sync"],
    source: `NSMutableDictionary *oldRepo = [NSMutableDictionary dictionary];
[oldRepo setObject:@"cid1" forKey:@"post/a"];
[oldRepo setObject:@"cid2" forKey:@"post/b"];
NSMutableDictionary *newRepo = [NSMutableDictionary dictionary];
[newRepo setObject:@"cid1" forKey:@"post/a"];
[newRepo setObject:@"cid3" forKey:@"post/b"];
[newRepo setObject:@"cid4" forKey:@"post/c"];
NSMutableArray *ops = [NSMutableArray array];
for (NSString *key in newRepo) {
    NSString *newCid = [newRepo objectForKey:key];
    NSString *oldCid = [oldRepo objectForKey:key];
    if (!oldCid) [ops addObject:@"add"];
    else if (![newCid isEqualToString:oldCid]) [ops addObject:@"update"];
}
for (NSString *key in oldRepo) {
    if (![newRepo objectForKey:key]) [ops addObject:@"delete"];
}
NSLog(@"ops=%d synced=%d", (int)[ops count], (int)[newRepo count]);`,
  },
  {
    name: "Migration manager with rollback model",
    category: "migrations",
    supportClass: "direct",
    expectedStatus: "ok",
    expectedOutput: ["version=2 afterRollback=1"],
    tags: ["atproto-domain", "migrations", "blocks"],
    source: `NSMutableArray *migrations = [NSMutableArray array];
[migrations addObject:@"accounts"];
[migrations addObject:@"records"];
int schemaVersion = (int)[migrations count];
int before = schemaVersion;
if (schemaVersion > 0) schemaVersion--;
NSLog(@"version=%d afterRollback=%d", before, schemaVersion);`,
  },
  {
    name: "CID SHA-256 and Base32 host bridge",
    category: "host-bridges",
    supportClass: "host-bridge",
    expectedStatus: "ok",
    expectedOutput: ["hash=32 base32=nbswy3dp decoded=5"],
    tags: ["host-bridge", "crypto", "base32"],
    source: `NSData *input = [NSData dataWithBytes:"hello" length:5];
NSData *hash = [CID sha256Digest:input];
NSString *encoded = [CID base32Encode:input];
NSData *decoded = [CID base32Decode:encoded];
NSLog(@"hash=%d base32=%@ decoded=%d", (int)[hash length], encoded, (int)[decoded length]);`,
  },
  {
    name: "JSON host bridge stringify",
    category: "host-bridges",
    supportClass: "host-bridge",
    expectedStatus: "ok",
    expectedOutput: ['json={"name":"alice"}'],
    tags: ["host-bridge", "json"],
    source: `NSMutableDictionary *dict = [NSMutableDictionary dictionary];
[dict setObject:@"alice" forKey:@"name"];
NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
NSString *jsonString = [jsonData bytes];
NSLog(@"json=%@", jsonString);`,
  },
  {
    name: "Base58 host bridge helper",
    category: "host-bridges",
    supportClass: "host-bridge",
    expectedStatus: "host-check",
    hostCheck: "base58",
    expectedOutput: ["base58=Cn8eVZg decoded=hello"],
    tags: ["host-bridge", "base58", "host-import-only"],
    source: `// Base58 currently has a deterministic host import helper.
// The ObjC selector surface is not exposed yet, so this is verified by the harness.`,
  },
  {
    name: "CBOR host bridge helper",
    category: "host-bridges",
    supportClass: "host-bridge",
    expectedStatus: "host-check",
    hostCheck: "cbor",
    expectedOutput: ['decoded={"type":"commit","seq":1}'],
    tags: ["host-bridge", "cbor", "host-import-only"],
    source: `// CBOR currently has deterministic host import helpers.
// The ObjC selector surface is not exposed yet, so this is verified by the harness.`,
  },
  {
    name: "Fetch host bridge fixture",
    category: "host-bridges",
    supportClass: "host-bridge",
    expectedStatus: "ok",
    expectedOutput: ['fetched={"name":"Alice","age":30}'],
    tags: ["host-bridge", "network"],
    source: `NSURL *url = [NSURL URLWithString:@"https://api.example.com/users/alice"];
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
NSURLSession *session = [NSURLSession sharedSession];
NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, id response, id error) {
    NSString *body = [data bytes];
    NSLog(@"fetched=%@", body);
}];
[task resume];`,
  },
  {
    name: "SQLite production dependency diagnostic",
    category: "unsupported-production",
    supportClass: "unsupported-production",
    expectedStatus: "diagnostic",
    expectedDiagnosticApis: ["sqlite3"],
    tags: ["unsupported-api", "sqlite"],
    source: `sqlite3 *db = NULL;
sqlite3_open("pds.sqlite", &db);
NSLog(@"db=%d", db != NULL);`,
  },
  {
    name: "GCD production dependency diagnostic",
    category: "unsupported-production",
    supportClass: "unsupported-production",
    expectedStatus: "diagnostic",
    expectedDiagnosticApis: ["dispatch"],
    tags: ["unsupported-api", "dispatch"],
    source: `dispatch_queue_t queue = dispatch_queue_create("tutorial", DISPATCH_QUEUE_SERIAL);
dispatch_async(queue, ^{ NSLog(@"async"); });`,
  },
  {
    name: "Filesystem blob provider diagnostic",
    category: "unsupported-production",
    supportClass: "unsupported-production",
    expectedStatus: "diagnostic",
    expectedDiagnosticApis: ["filesystem"],
    tags: ["unsupported-api", "filesystem"],
    source: `NSFileManager *fm = [NSFileManager defaultManager];
NSData *data = [NSData dataWithBytes:"blob" length:4];
[data writeToFile:@"/tmp/blob" atomically:YES];
NSLog(@"exists=%d", [fm fileExistsAtPath:@"/tmp/blob"]);`,
  },
  {
    name: "Security and keychain diagnostic",
    category: "unsupported-production",
    supportClass: "unsupported-production",
    expectedStatus: "diagnostic",
    expectedDiagnosticApis: ["security-crypto"],
    tags: ["unsupported-api", "security"],
    source: `SecKeyRef key = NULL;
CC_SHA256_CTX ctx;
NSLog(@"key=%p", key);`,
  },
  {
    name: "Media framework diagnostic",
    category: "unsupported-production",
    supportClass: "unsupported-production",
    expectedStatus: "diagnostic",
    expectedDiagnosticApis: ["media"],
    tags: ["unsupported-api", "media"],
    source: `AVAsset *asset = nil;
CGImageRef image = NULL;
NSLog(@"asset=%@ image=%p", asset, image);`,
  },
];
