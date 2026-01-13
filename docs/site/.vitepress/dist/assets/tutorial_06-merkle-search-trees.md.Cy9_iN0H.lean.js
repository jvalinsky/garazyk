import{C as t,c as l,o as h,ag as i,G as n}from"./chunks/framework.EuUYIJ38.js";const o=JSON.parse('{"title":"Chapter 6: Merkle Search Trees","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/06-merkle-search-trees.md","filePath":"tutorial/06-merkle-search-trees.md"}'),k={name:"tutorial/06-merkle-search-trees.md"},y=Object.assign(k,{setup(r){const e=`#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

uint32_t keyDepth(NSString *key) {
    if (!key) return 0;
    
    // 1. Hash the key (SHA-256)
    const char *utf8 = [key UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8, (CC_LONG)strlen(utf8), hash);

    // 2. Count leading zero bits (in nibbles/half-bytes)
    uint32_t zeroCount = 0;

    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];

        if (byte == 0) {
            zeroCount += 4; // 2 nibbles
            continue;
        }

        // First non-zero byte
        if ((byte & 0xC0) == 0) zeroCount++; // 11...
        if ((byte & 0xF0) == 0) zeroCount++; // 0011...
        // Note: simplified counting for demonstration
        // Just checking top bits for 0s
        if ((byte & 0xFC) == 0) zeroCount += 3;
        else if ((byte & 0xF0) == 0) zeroCount += 2;
        else if ((byte & 0xC0) == 0) zeroCount += 1;
        
        break;
    }
    
    return zeroCount;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *keys = @[
            @"app.bsky.feed.post/123",
            @"app.bsky.feed.post/456",
            @"app.bsky.feed.post/789",
            @"app.bsky.feed.like/common",
            @"app.bsky.feed.like/rare"
        ];
        
        for (NSString *key in keys) {
            printf("Depth: %u  Key: %s\\n", keyDepth(key), key.UTF8String);
        }
    }
    return 0;
}`,p=`#import <Foundation/Foundation.h>

void compressKeys(NSArray<NSString *> *keys) {
    NSString *prevKey = @"";
    printf("Compression Analysis:\\n");
    printf("---------------------\\n");
    
    for (NSString *key in keys) {
        NSUInteger prefixLen = 0;
        NSUInteger minLen = MIN(prevKey.length, key.length);
        
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [key characterAtIndex:i]) {
                prefixLen++;
            } else {
                break;
            }
        }
        
        NSString *suffix = [key substringFromIndex:prefixLen];
        printf("Key:    %s\\n", key.UTF8String);
        printf("Prefix: %lu chars shared with '%s'\\n", (unsigned long)prefixLen, prevKey.UTF8String);
        printf("Suffix: %s\\n", suffix.UTF8String);
        printf("Status: %s\\n\\n", prefixLen > 0 ? "COMPRESSED" : "FULL KEY");
        
        prevKey = key;
    }
}

int main() {
    @autoreleasepool {
        NSArray *keys = @[
            @"app.bsky.feed.post/abc",
            @"app.bsky.feed.post/xyz",
            @"app.bsky.feed.post/zzz"
        ];
        compressKeys(keys);
    }
    return 0;
}`;return(d,s)=>{const a=t("ObjcRunner");return h(),l("div",null,[s[0]||(s[0]=i("",57)),n(a,{initialCode:e}),s[1]||(s[1]=i("",34)),n(a,{initialCode:p}),s[2]||(s[2]=i("",83))])}}});export{o as __pageData,y as default};
