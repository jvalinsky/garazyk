import{C as t,c as h,o as p,ag as i,G as l}from"./chunks/framework.EuUYIJ38.js";const d=JSON.parse('{"title":"Chapter 10: PLC Operations & Account Creation","description":"","frontmatter":{},"headers":[],"relativePath":"tutorial/10-plc-operations.md","filePath":"tutorial/10-plc-operations.md"}'),e={name:"tutorial/10-plc-operations.md"},g=Object.assign(e,{setup(k){const a=`#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        printf("--- PLC Genesis Operation Builder ---\\n");

        // 1. Define Identity Components
        NSString *signingKey = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        NSString *recoveryKey = @"did:key:zQ3abc...";
        NSString *handle = @"alice.bsky.social";
        NSString *pds = @"https://pds.example.com";

        // 2. Build Operation Dictionary
        NSMutableDictionary *op = [NSMutableDictionary dictionary];
        op[@"type"] = @"plc_operation";
        op[@"prev"] = [NSNull null];
        
        // Rotation keys (Recovery first, then Signing)
        op[@"rotationKeys"] = @[recoveryKey, signingKey];
        
        // Verification methods
        op[@"verificationMethods"] = @{@"atproto": signingKey};
        
        // Handle (alias)
        op[@"alsoKnownAs"] = @[[NSString stringWithFormat:@"at://%@", handle]];
        
        // Services (PDS endpoint)
        op[@"services"] = @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": pds
            }
        };

        // 3. Serialize for Signing (Mock step - real app uses DAG-CBOR)
        printf("Signing operation with Recovery Key...\\n");
        // In reality: sign(DAG_CBOR(op_without_sig))
        op[@"sig"] = @"mock_signature_base64url_xyz123";

        // 4. Output resulting JSON
        NSData *json = [NSJSONSerialization dataWithJSONObject:op options:NSJSONWritingPrettyPrinted error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        
        printf("Genesis Operation:\\n%s\\n", jsonStr.UTF8String);
        
        // 5. Compute DID (Mock)
        // In reality: SHA256(DAG_CBOR(op)) -> CID -> did:plc
        printf("\\nDerived DID: did:plc:z72i7hdynmk6r22z27h6tvur\\n");
    }
    return 0;
}`;return(r,s)=>{const n=t("ObjcRunner");return p(),h("div",null,[s[0]||(s[0]=i("",71)),l(n,{initialCode:a}),s[1]||(s[1]=i("",85))])}}});export{d as __pageData,g as default};
