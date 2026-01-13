import{C as t,c as h,o as l,ag as i,G as k}from"./chunks/framework.EuUYIJ38.js";const g=JSON.parse('{"title":"Chapter 15: Complete PDS Integration","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/15-complete-pds.md","filePath":"tutorial/15-complete-pds.md"}'),p={name:"tutorial/15-complete-pds.md"},y=Object.assign(p,{setup(e){const a=`#import <Foundation/Foundation.h>

// --- Mock PDS Client for Integration Tests ---

@interface PDSClient : NSObject
@property (nonatomic, strong) NSMutableDictionary *serverState; // "DB"
@end

@implementation PDSClient
- (instancetype)init { self=[super init]; _serverState=[NSMutableDictionary dictionary]; return self; }

- (void)createAccount:(NSString *)handle password:(NSString *)password {
    self.serverState[handle] = password;
    printf("Client: Account created for %s\\n", handle.UTF8String);
}

- (NSString *)authenticate:(NSString *)handle password:(NSString *)password {
    if ([self.serverState[handle] isEqualToString:password]) {
        printf("Client: Authenticated %s\\n", handle.UTF8String);
        return [NSString stringWithFormat:@"token_for_%@", handle];
    }
    printf("Client: Auth failed for %s\\n", handle.UTF8String);
    return nil;
}

- (void)createRecord:(NSString *)token collection:(NSString *)collection record:(NSDictionary *)record {
    if (!token) { printf("Client: 401 Unauthorized\\n"); return; }
    NSString *key = [NSString stringWithFormat:@"%@/%@", token, collection];
    self.serverState[key] = record;
    printf("Client: Created record in %s\\n", collection.UTF8String);
}

- (NSDictionary *)getRecord:(NSString *)token collection:(NSString *)collection {
    NSString *key = [NSString stringWithFormat:@"%@/%@", token, collection];
    return self.serverState[key];
}
@end
`+`
// --- EXERCISE 3: Integration Test ---

void runTest() {
    PDSClient *client = [PDSClient new];
    
    // TODO: Implement the integration flow
    // 1. Create account "alice" with password "secure"
    // 2. Authenticate to get token
    // 3. Create a record in "app.bsky.feed.post" with text "Hello"
    // 4. Get the record back and verify text is "Hello"
    
    // Example:
    // [client createAccount:@"alice" password:@"secure"];
    // NSString *token = [client authenticate:@"alice" password:@"secure"];
    // ...
    
    // Your validation code here
    
    // Check (Mock verification)
    NSDictionary *rec = [client getRecord:@"token_for_alice" collection:@"app.bsky.feed.post"];
    if (rec && [rec[@"text"] isEqualToString:@"Hello"]) {
        printf("PASS: Integration test successful.\\n");
    } else {
        printf("FAIL: Record verification failed.\\n");
    }
}

int main() {
    @autoreleasepool {
        runTest();
    }
    return 0;
}`;return(E,s)=>{const n=t("ObjcRunner");return l(),h("div",null,[s[0]||(s[0]=i("",48)),k(n,{initialCode:a}),s[1]||(s[1]=i("",12))])}}});export{g as __pageData,y as default};
