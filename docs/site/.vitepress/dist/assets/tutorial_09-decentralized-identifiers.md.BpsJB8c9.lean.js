import{C as d,c as o,o as E,ag as e,G as n,j as i,a as l}from"./chunks/framework.EuUYIJ38.js";const F=JSON.parse('{"title":"Chapter 9: Decentralized Identifiers (DIDs)","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/09-decentralized-identifiers.md","filePath":"tutorial/09-decentralized-identifiers.md"}'),g={name:"tutorial/09-decentralized-identifiers.md"},D=Object.assign(g,{setup(y){const t=`#import <Foundation/Foundation.h>

// --- Base58 Helper ---
static const char base58Alphabet[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

NSData *base58Decode(NSString *string) {
    if (string.length == 0) return [NSData data];
    NSUInteger zeroCount = 0;
    while (zeroCount < string.length && [string characterAtIndex:zeroCount] == '1') zeroCount++;
    
    // Simple decoding (mock-ish but functional)
    // For full implementation see tutorial text.
    // This decoder is sufficient for the demo strings.
    
    // ... (Compact decoder)
    NSUInteger maxSize = string.length * 733 / 1000 + 1;
    uint8_t *output = calloc(maxSize, 1);
    NSUInteger outputLength = 1;
    
    for (NSUInteger i = zeroCount; i < string.length; i++) {
        const char *p = strchr(base58Alphabet, [string characterAtIndex:i]);
        if (!p) { free(output); return nil; }
        uint8_t digit = p - base58Alphabet;
        uint16_t carry = digit;
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = output[j] * 58 + carry;
            output[j] = product % 256;
            carry = product / 256;
        }
        while (carry) output[outputLength++] = carry % 256;
    }
    
    NSMutableData *res = [NSMutableData dataWithLength:zeroCount + outputLength];
    uint8_t *bytes = res.mutableBytes;
    for (NSUInteger i = 0; i < outputLength; i++) bytes[zeroCount + i] = output[outputLength - 1 - i];
    free(output);
    return res;
}

NSString *base58Encode(NSData *data) {
    if (data.length == 0) return @"";
    const uint8_t *input = data.bytes;
    NSUInteger len = data.length;
    NSUInteger zeroCount = 0;
    while (zeroCount < len && input[zeroCount] == 0) zeroCount++;
    
    NSUInteger maxSize = len * 138 / 100 + 1;
    uint8_t *output = calloc(maxSize, 1);
    NSUInteger outputLength = 1;

    for (NSUInteger i = zeroCount; i < len; i++) {
        uint16_t carry = input[i];
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = output[j] * 256 + carry;
            output[j] = product % 58;
            carry = product / 58;
        }
        while (carry) output[outputLength++] = carry % 58;
    }

    NSMutableString *res = [NSMutableString string];
    for (NSUInteger i = 0; i < zeroCount; i++) [res appendString:@"1"];
    for (NSUInteger i = outputLength; i > 0; i--) [res appendFormat:@"%c", base58Alphabet[output[i-1]]];
    free(output);
    return res;
}
`,p=t+`
void parseDIDKey(NSString *did) {
    printf("Parsing: %s\\n", did.UTF8String);
    if (![did hasPrefix:@"did:key:z"]) {
        printf("Error: Invalid prefix.\\n");
        return;
    }
    NSString *encoded = [did substringFromIndex:9];
    NSData *data = base58Decode(encoded);
    if (!data) { printf("Error: Invalid Base58.\\n"); return; }
    
    const uint8_t *bytes = data.bytes;
    if (data.length > 2 && bytes[0] == 0xE7 && bytes[1] == 0x01) {
        printf("Key Type:  secp256k1 (0xe701)\\n");
        NSData *pubKey = [data subdataWithRange:NSMakeRange(2, data.length - 2)];
        printf("Public Key: %s... (%lu bytes)\\n", 
               [pubKey subdataWithRange:NSMakeRange(0, 4)].description.UTF8String, 
               pubKey.length);
    } else {
        printf("Key Type:  Unknown\\n");
    }
    printf("\\n");
}

int main() {
    @autoreleasepool {
        parseDIDKey(@"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme");
    }
    return 0;
}`,h=t+`
// --- EXERCISE 1: Hand-Encode did:key ---

NSString * encodeDIDKey(NSData *compressedPubKey) {
    // TODO:
    // 1. Create mutable data
    // 2. Append multicodec prefix (0xe7, 0x01)
    // 3. Append public key
    // 4. Base58 encode
    // 5. Prepend "did:key:z"
    
    return @""; // Replace this
}

int main() {
    @autoreleasepool {
        // Example Key: 0x02b1f4...
        uint8_t k[] = {0x02, 0xb1, 0xf4, 0x8e, 0xc4, 0xa9, 0x2a, 0x8f, 0x1f, 0x99, 
                       0x4b, 0xdc, 0x8e, 0x00, 0x52, 0xbc, 0xe9, 0xd3, 0x97, 0x76, 
                       0xb4, 0x6b, 0x01, 0xb9, 0xe7, 0xc0, 0xf2, 0xe3, 0x1c, 0x7a, 
                       0xe4, 0xed, 0x9c};
        NSData *pub = [NSData dataWithBytes:k length:33];
        
        NSString *did = encodeDIDKey(pub);
        printf("Result: %s\\n", did.UTF8String);
        
        NSString *expected = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        if ([did isEqualToString:expected]) {
            printf("PASS: Correctly encoded.\\n");
        } else {
            printf("FAIL: Expected %s\\n", expected.UTF8String);
        }
    }
    return 0;
}`,k=t+`
// --- EXERCISE 2: Identify Key Type ---

NSString * identifyKeyType(NSString *did) {
    // TODO:
    // 1. Strip prefix
    // 2. Decode Base58
    // 3. Check first byte(s)
    // Return @"secp256k1", @"ed25519", or @"unknown"
    
    // Hint: secp256k1 = 0xe7, ed25519 = 0xed
    
    return @"unknown";
}

int main() {
    @autoreleasepool {
        NSString *d1 = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        NSString *d2 = @"did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK";
        
        printf("DID 1: %s\\n", identifyKeyType(d1).UTF8String);
        printf("DID 2: %s\\n", identifyKeyType(d2).UTF8String);
        
        if ([identifyKeyType(d1) isEqualToString:@"secp256k1"] && 
            [identifyKeyType(d2) isEqualToString:@"ed25519"]) {
            printf("PASS: Identified correctly.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`,r=`#import <Foundation/Foundation.h>

// --- EXERCISE 3: Key Rotation Op Builder ---

NSDictionary * buildUpdateOp(NSString *did, NSString *newKeyDID, NSString *prevOpHash) {
    // TODO: Build the dictionary for a PLC update operation
    // Fields: type="update", rotationKeys=[newKeyDID], alsoKnownAs, services...
    // For this exercise, focus on rotating the signing key.
    
    return @{};
}

int main() {
    @autoreleasepool {
        NSDictionary *op = buildUpdateOp(@"did:plc:123", @"did:key:zNew...", @"bafyPrev");
        
        printf("Op Type: %s\\n", [op[@"type"] UTF8String]);
        NSArray *keys = op[@"rotationKeys"];
        if (keys.count > 0) {
            printf("New Key: %s\\n", [keys[0] UTF8String]);
        }
        
        if ([op[@"type"] isEqualToString:@"update"] && [keys containsObject:@"did:key:zNew..."]) {
            printf("PASS: Operation structure correct.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`;return(c,s)=>{const a=d("ObjcRunner");return E(),o("div",null,[s[0]||(s[0]=e("",175)),n(a,{initialCode:p}),s[1]||(s[1]=e("",124)),n(a,{initialCode:h}),s[2]||(s[2]=i("h3",{id:"📝-exercise-2-identify-key-types-from-dids",tabindex:"-1"},[l("📝 Exercise 2: Identify Key Types from DIDs "),i("a",{class:"header-anchor",href:"#📝-exercise-2-identify-key-types-from-dids","aria-label":'Permalink to "📝 Exercise 2: Identify Key Types from DIDs"'},"​")],-1)),s[3]||(s[3]=i("p",null,"For each DID, determine the key type:",-1)),s[4]||(s[4]=i("ol",null,[i("li",null,[i("code",null,"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme")]),i("li",null,[i("code",null,"did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK")])],-1)),n(a,{initialCode:k}),s[5]||(s[5]=i("h3",{id:"📝-exercise-3-op-builder",tabindex:"-1"},[l("📝 Exercise 3: Op Builder "),i("a",{class:"header-anchor",href:"#📝-exercise-3-op-builder","aria-label":'Permalink to "📝 Exercise 3: Op Builder"'},"​")],-1)),s[6]||(s[6]=i("p",null,"Implement a method to build a PLC update operation dictionary:",-1)),n(a,{initialCode:r}),s[7]||(s[7]=e("",41))])}}});export{F as __pageData,D as default};
