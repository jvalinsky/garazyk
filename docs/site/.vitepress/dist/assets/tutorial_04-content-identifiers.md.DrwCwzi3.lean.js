import{C as l,c as k,o as p,ag as i,G as n}from"./chunks/framework.EuUYIJ38.js";const g=JSON.parse('{"title":"Chapter 4: Content Identifiers (CIDs) & Hashing","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/04-content-identifiers.md","filePath":"tutorial/04-content-identifiers.md"}'),e={name:"tutorial/04-content-identifiers.md"},y=Object.assign(e,{setup(r){const t=`#import <Foundation/Foundation.h>

void encodeVarint(uint64_t value) {
    NSMutableData *data = [NSMutableData dataWithCapacity:9];
    uint64_t v = value;
    
    do {
        uint8_t byte = v & 0x7F;  // Take low 7 bits
        v >>= 7;                   // Shift by 7
        if (v != 0) {
            byte |= 0x80;          // Set continuation bit
        }
        [data appendBytes:&byte length:1];
    } while (v != 0);
    
    NSLog(@"Value: %llu (0x%llX) -> Encoded: %@", value, value, data);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        encodeVarint(0x01);    // 1
        encodeVarint(0x71);    // 113
        encodeVarint(0x200);   // 512
        encodeVarint(0xFACE);  // 64206
    }
    return 0;
}`,h=`static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

NSString *base32Encode(NSData *data) {
    if (!data || data.length == 0) return @"";

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableString *result = [NSMutableString string];

    uint64_t buffer = 0;
    int bitsLeft = 0;
    
    for (NSUInteger i = 0; i < length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bitsLeft += 8;
        
        while (bitsLeft >= 5) {
            int shift = bitsLeft - 5;
            [result appendFormat:@"%c", kBase32Alphabet[(buffer >> shift) & 0x1F]];
            bitsLeft -= 5;
        }
        buffer &= ((1ULL << bitsLeft) - 1);
    }

    if (bitsLeft > 0) {
        [result appendFormat:@"%c", kBase32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]];
    }

    return [result copy];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSData *hello = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSLog(@"Input: %@", [[NSString alloc] initWithData:hello encoding:NSUTF8StringEncoding]);
        NSLog(@"Base32: %@", base32Encode(hello));
    }
    return 0;
}`;return(d,s)=>{const a=l("ObjcRunner");return p(),k("div",null,[s[0]||(s[0]=i("",19)),n(a,{initialCode:t}),s[1]||(s[1]=i("",16)),n(a,{initialCode:h}),s[2]||(s[2]=i("",59))])}}});export{g as __pageData,y as default};
