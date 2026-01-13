import{C as l,c as p,o as k,ag as i,G as t}from"./chunks/framework.EuUYIJ38.js";const g=JSON.parse('{"title":"Chapter 14: OAuth 2.1 & JWT Authentication","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/14-oauth-jwt.md","filePath":"tutorial/14-oauth-jwt.md"}'),r={name:"tutorial/14-oauth-jwt.md"},y=Object.assign(r,{setup(d){const a=`#import <Foundation/Foundation.h>

// --- Mock JWT Classes ---

@interface JWTHeader : NSObject
@property (nonatomic, copy) NSString *alg;
@property (nonatomic, copy) NSString *typ;
@end
@implementation JWTHeader
@end

@interface JWTPayload : NSObject
@property (nonatomic, copy) NSString *iss;
@property (nonatomic, copy) NSString *sub;
@property (nonatomic, copy) NSDate *exp;
@end
@implementation JWTPayload
@end

@interface JWT : NSObject
@property (nonatomic, strong) JWTHeader *header;
@property (nonatomic, strong) JWTPayload *payload;
@property (nonatomic, copy) NSString *encodedSignature;
@end
@implementation JWT
- (instancetype)init { self=[super init]; _header=[JWTHeader new]; _payload=[JWTPayload new]; return self; }
@end
`,h=a+`
// --- EXERCISE 1: Base64URL Decoding ---

NSString *base64URLDecode(NSString *str) {
    // TODO: Implement Base64URL decoding
    // 1. Replace '-' -> '+', '_' -> '/'
    // 2. Add padding '=' to length % 4
    // 3. Decode Base64 string to NSString (assuming UTF8)
    return nil;
}

void runDemo() {
    // Example: "SGVsbG8tV29ybGQ" -> "Hello-World"
    // Standard Base64: "SGVsbG8tV29ybGQ=" (if padded) -> "Hello-World" logic
    
    // Test Case: "eyJuYW1lIjoiQWxpY2UifQ" -> {"name":"Alice"}
    NSString *input = @"eyJuYW1lIjoiQWxpY2UifQ";
    NSString *output = base64URLDecode(input);
    
    printf("Input: %s\\n", input.UTF8String);
    printf("Output: %s\\n", output.UTF8String);
    
    if ([output isEqualToString:@"{\\"name\\":\\"Alice\\"}"]) {
        printf("PASS: Correctly decoded.\\n");
    } else {
        printf("FAIL.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`,e=a+`
// --- EXERCISE 2: Expiration Check ---

@implementation JWT (Exercise2)
- (BOOL)isExpired {
    // TODO: Check if self.payload.exp is before [NSDate date]
    return NO;
}
@end

void runDemo() {
    JWT *jwt = [JWT new];
    // Case 1: Expired
    jwt.payload.exp = [NSDate dateWithTimeIntervalSinceNow:-3600]; // 1 hour ago
    
    BOOL expired1 = [jwt isExpired];
    printf("Case 1 (Past): %s\\n", expired1 ? "Expired (PASS)" : "Valid (FAIL)");
    
    // Case 2: Future
    jwt.payload.exp = [NSDate dateWithTimeIntervalSinceNow:3600]; // 1 hour future
    BOOL expired2 = [jwt isExpired];
    printf("Case 2 (Future): %s\\n", expired2 ? "Expired (FAIL)" : "Valid (PASS)");
    
    if (expired1 && !expired2) {
        printf("ALL TESTS PASSED.\\n");
    }
}

int main() {
    @autoreleasepool {
        runDemo();
    }
    return 0;
}`;return(E,s)=>{const n=l("ObjcRunner");return k(),p("div",null,[s[0]||(s[0]=i("",285)),t(n,{initialCode:h}),s[1]||(s[1]=i("",3)),t(n,{initialCode:e}),s[2]||(s[2]=i("",44))])}}});export{g as __pageData,y as default};
