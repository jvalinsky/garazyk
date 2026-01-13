import{C as e,c as t,o as l,ag as i,G as p}from"./chunks/framework.EuUYIJ38.js";const o=JSON.parse('{"title":"Chapter 3: Build Systems & Project Structure","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/03-build-systems.md","filePath":"tutorial/03-build-systems.md"}'),h={name:"tutorial/03-build-systems.md"},E=Object.assign(h,{setup(k){const a=`#import <Foundation/Foundation.h>

// PDSConfig Interface
@interface PDSConfig : NSObject
@property (readonly, nonatomic, copy) NSString *hostname;
@property (readonly, nonatomic) NSUInteger port;
@property (readonly, nonatomic, copy) NSString *databasePath;
+ (instancetype)loadFromPath:(NSString *)path error:(NSError **)error;
@end

// PDSConfig Implementation
@implementation PDSConfig
+ (instancetype)loadFromPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    
    PDSConfig *config = [[PDSConfig alloc] init];
    config->_hostname = [json[@"hostname"] copy];
    config->_port = [json[@"port"] unsignedIntegerValue];
    config->_databasePath = [json[@"databasePath"] copy];
    return config;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"Server running at %@:%lu (DB: %@)", 
            self.hostname, (unsigned long)self.port, self.databasePath];
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 1. Create a dummy config file
        NSString *json = @"{\\"hostname\\": \\"bsky.social\\", \\"port\\": 3000, \\"databasePath\\": \\"pds.sqlite\\"}";
        NSString *path = @"/tmp/config.json";
        [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // 2. Load it using our class
        NSError *error = nil;
        PDSConfig *config = [PDSConfig loadFromPath:path error:&error];
        
        if (config) {
            NSLog(@"✅ Loaded Config: %@", config);
        } else {
            NSLog(@"❌ Error: %@", error);
        }
    }
    return 0;
}`;return(r,s)=>{const n=e("ObjcRunner");return l(),t("div",null,[s[0]||(s[0]=i("",48)),p(n,{initialCode:a}),s[1]||(s[1]=i("",34))])}}});export{o as __pageData,E as default};
