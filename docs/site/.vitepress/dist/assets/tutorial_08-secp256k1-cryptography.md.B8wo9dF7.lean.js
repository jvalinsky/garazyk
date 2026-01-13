import{C as e,c as r,o as E,ag as i,G as h}from"./chunks/framework.EuUYIJ38.js";const o=JSON.parse('{"title":"Chapter 8: Elliptic Curve Cryptography with secp256k1","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/08-secp256k1-cryptography.md","filePath":"tutorial/08-secp256k1-cryptography.md"}'),d={name:"tutorial/08-secp256k1-cryptography.md"},F=Object.assign(d,{setup(y){const a=`#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

// --- Helper: SHA256 ---
NSData *sha256(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
NSString *hex(NSData *d) {
    const unsigned char *bytes = (const unsigned char *)d.bytes;
    NSMutableString *str = [NSMutableString stringWithCapacity:d.length * 2];
    for (int i=0; i<d.length; i++) [str appendFormat:@"%02x", bytes[i]];
    return str;
}

// --- Smart Mock Secp256k1 ---
// Uses symmetric crypto (Pub = Priv) for simplicity in demo
// Signature = SHA256(Priv + Hash)
@interface Secp256k1KeyPair : NSObject
@property (readonly) NSData *privateKey;
@property (readonly) NSData *publicKey;
@property (readonly) NSData *compressedPublicKey;
+ (instancetype)generateKeyPair:(NSError **)error;
+ (instancetype)keyPairWithPriv:(NSData *)p;
- (NSData *)signHash:(NSData *)hash error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h error:(NSError **)error;
// Helper for verification without key instance
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h withPublicKey:(NSData *)pub error:(NSError **)error;
@end

@implementation Secp256k1KeyPair
+ (instancetype)generateKeyPair:(NSError **)error {
    // Randomish seed based on time
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSData *seed = [NSData dataWithBytes:&t length:sizeof(t)];
    return [self keyPairWithPriv:sha256(seed)];
}
+ (instancetype)keyPairWithPriv:(NSData *)p {
    Secp256k1KeyPair *k = [Secp256k1KeyPair new];
    k->_privateKey = p;
    k->_publicKey = p; // Symmetric Mock
    k->_compressedPublicKey = p;
    return k;
}
- (NSData *)signHash:(NSData *)hash error:(NSError **)error {
    NSMutableData *d = [NSMutableData dataWithData:self.privateKey];
    [d appendData:hash];
    return sha256(d);
}
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h error:(NSError **)error {
    return [self verifySignature:sig forHash:h withPublicKey:self.publicKey error:error];
}
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h withPublicKey:(NSData *)pub error:(NSError **)error {
    NSMutableData *d = [NSMutableData dataWithData:pub]; // Use pub key for verification
    [d appendData:h];
    NSData *computed = sha256(d);
    return [computed isEqualToData:sig];
}
@end
`,t=a+`
int main() {
    @autoreleasepool {
        printf("--- Crypto Demo (Smart Mock) ---\\n");
        
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
        printf("Key 1 Pub: %s\\n", hex(k1.publicKey).UTF8String);
        
        NSData *msg = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *h = sha256(msg);
        
        NSData *sig = [k1 signHash:h error:nil];
        printf("Signature: %s\\n", hex(sig).UTF8String);
        
        BOOL v = [k1 verifySignature:sig forHash:h error:nil];
        printf("Verify K1: %s\\n", v ? "YES" : "NO");
    }
    return 0;
}`,k=a+`
// --- EXERCISE 1: Cross-Verification Failure ---

void testWrongKeyRejected() {
    // TODO: 
    // 1. Generate KeyPair 1 and KeyPair 2
    // 2. Sign a hash with KeyPair 1
    // 3. Try to verify signature using KeyPair 2's public key
    // 4. Print PASS if verification fails (returns NO)
    
    printf("Running testWrongKeyRejected...\\n");
    
    Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
    Secp256k1KeyPair *k2 = [Secp256k1KeyPair generateKeyPair:nil];
    
    NSData *h = sha256([@"test" dataUsingEncoding:NSUTF8StringEncoding]);
    NSData *sig = [k1 signHash:h error:nil];
    
    // Verify with k2 (Mock: manually check logic)
    // Note: Our mock class instance method uses its own pub key.
    // To verify with k2 against k2's pub key (which would be invalid for k1's sig):
    BOOL valid = [k2 verifySignature:sig forHash:h error:nil];
    
    if (valid == NO) {
        printf("PASS: Signature from K1 rejected by K2.\\n");
    } else {
        printf("FAIL: K2 accepted K1's signature! (Collision?)\\n");
    }
}

int main() {
    @autoreleasepool {
        testWrongKeyRejected();
    }
    return 0;
}`,p=a+`
// --- EXERCISE 2: Deterministic Key Gen ---

@interface Secp256k1KeyPair (Seed)
+ (instancetype)keyPairFromSeed:(NSData *)seed;
@end

@implementation Secp256k1KeyPair (Seed)
+ (instancetype)keyPairFromSeed:(NSData *)seed {
    // TODO: Implement deterministic generation
    // Hint: Use sha256(seed) as the private key
    // Use [self keyPairWithPriv:...] from the mock
    
    return nil; // Replace this
}
@end

int main() {
    @autoreleasepool {
        NSData *seed = [@"my_secret_seed" dataUsingEncoding:NSUTF8StringEncoding];
        
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair keyPairFromSeed:seed];
        if (!k1) { printf("Not implemented yet.\\n"); return 0; }
        
        Secp256k1KeyPair *k2 = [Secp256k1KeyPair keyPairFromSeed:seed];
        
        printf("K1 Pub: %s\\n", hex(k1.publicKey).UTF8String);
        printf("K2 Pub: %s\\n", hex(k2.publicKey).UTF8String);
        
        if ([k1.publicKey isEqualToData:k2.publicKey]) {
            printf("PASS: Keys are deterministic.\\n");
        } else {
            printf("FAIL: Keys differ for same seed.\\n");
        }
    }
    return 0;
}`,l=a+`
// --- EXERCISE 3: Batch Verification ---

// Item: @{@"sig": NSData, @"hash": NSData, @"pub": NSData}
NSArray<NSNumber *> * verifyBatch(NSArray<NSDictionary *> *items) {
    NSMutableArray *results = [NSMutableArray array];
    
    // TODO: Loop through items and verify each
    // Hint: Create temp key pair to reuse verify logic? 
    // Or add a static verify helper to the mock.
    // (Added verifySignature:forHash:withPublicKey: to mock for you)
    
    Secp256k1KeyPair *verifier = [Secp256k1KeyPair new];
    for (NSDictionary *item in items) {
        BOOL v = [verifier verifySignature:item[@"sig"] 
                                   forHash:item[@"hash"] 
                             withPublicKey:item[@"pub"] 
                                     error:nil];
        [results addObject:@(v)];
    }
    
    return results;
}

int main() {
    @autoreleasepool {
        // Setup Success Case
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
        NSData *h1 = sha256([@"msg1" dataUsingEncoding:NSUTF8StringEncoding]);
        NSData *s1 = [k1 signHash:h1 error:nil];
        
        // Setup Fail Case (Wrong Key)
        Secp256k1KeyPair *k2 = [Secp256k1KeyPair generateKeyPair:nil];
        
        NSArray *batch = @[
            @{ @"sig": s1, @"hash": h1, @"pub": k1.publicKey }, // Valid
            @{ @"sig": s1, @"hash": h1, @"pub": k2.publicKey }  // Invalid
        ];
        
        NSArray *res = verifyBatch(batch);
        printf("Results: %s, %s\\n", 
               res[0].boolValue ? "YES" : "NO", 
               res[1].boolValue ? "YES" : "NO");
               
        if (res[0].boolValue && !res[1].boolValue) {
            printf("PASS: Batch verification correct.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`;return(g,s)=>{const n=e("ObjcRunner");return E(),r("div",null,[s[0]||(s[0]=i("",21)),h(n,{initialCode:t}),s[1]||(s[1]=i("",35)),h(n,{initialCode:k}),s[2]||(s[2]=i("",4)),h(n,{initialCode:p}),s[3]||(s[3]=i("",4)),h(n,{initialCode:l}),s[4]||(s[4]=i("",11))])}}});export{o as __pageData,F as default};
