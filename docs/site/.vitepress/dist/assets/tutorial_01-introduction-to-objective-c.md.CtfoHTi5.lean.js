import{C as t,c as h,o as l,ag as i,G as e}from"./chunks/framework.EuUYIJ38.js";const E=JSON.parse('{"title":"Chapter 1: Introduction to Objective-C","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/01-introduction-to-objective-c.md","filePath":"tutorial/01-introduction-to-objective-c.md"}'),p={name:"tutorial/01-introduction-to-objective-c.md"},o=Object.assign(p,{setup(k){const a=`#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Hello from the AT Protocol tutorial!");
        
        NSArray *features = @[@"DIDs", @"MSTs", @"CAR files"];
        for (NSString *feature in features) {
            NSLog(@"Learning about: %@", feature);
        }
    }
    return 0;
}`;return(r,s)=>{const n=t("ObjcRunner");return l(),h("div",null,[s[0]||(s[0]=i("",7)),e(n,{initialCode:a}),s[1]||(s[1]=i("",95))])}}});export{E as __pageData,o as default};
