import{C as h,c as t,o as l,ag as i,G as k}from"./chunks/framework.EuUYIJ38.js";const d=JSON.parse('{"title":"Chapter 2: The Foundation Framework","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/02-foundation-framework.md","filePath":"tutorial/02-foundation-framework.md"}'),p={name:"tutorial/02-foundation-framework.md"},g=Object.assign(p,{setup(e){const a=`#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // NSString Operations
        NSString *handle = @"alice.bsky.social";
        NSLog(@"Handle: %@", handle);
        
        if ([handle hasSuffix:@".bsky.social"]) {
            NSLog(@"✅ Valid domain");
        }
        
        // NSArray & Components
        NSArray *parts = [handle componentsSeparatedByString:@"."];
        NSLog(@"Parts: %@", parts);
        
        // NSDictionary
        NSDictionary *repo = @{
            @"handle": handle,
            @"did": @"did:plc:z72i7hd...",
            @"collections": @[@"app.bsky.feed.post", @"app.bsky.graph.follow"]
        };
        
        NSLog(@"Repo Data: %@", repo);
    }
    return 0;
}`;return(r,s)=>{const n=h("ObjcRunner");return l(),t("div",null,[s[0]||(s[0]=i("",10)),k(n,{initialCode:a}),s[1]||(s[1]=i("",91))])}}});export{d as __pageData,g as default};
