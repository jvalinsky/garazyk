#import <XCTest/XCTest.h>
#import "Repository/RepoCommit.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Auth/Secp256k1.h"
#import "Auth/PDSAppleKeyManager.h"

@interface RepoCommitTests : XCTestCase

@end

@implementation RepoCommitTests

- (void)testCommitCreation {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    XCTAssertNotNil(commit, @"Commit should be created");
    XCTAssertEqualObjects(commit.did, did, @"DID should match");
    XCTAssertEqualObjects(commit.dataCID, dataCID, @"Data CID should match");
    XCTAssertEqualObjects(commit.rev, rev, @"Rev should match");
    XCTAssertEqual(commit.version, 3, @"Version should be 3");
    XCTAssertNil(commit.prevCID, @"Prev CID should be nil");
    XCTAssertNil(commit.signature, @"Signature should be nil before signing");
}

- (void)testCommitCreationWithPrev {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    CID *prevCID = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:prevCID];
    
    XCTAssertNotNil(commit, @"Commit should be created");
    XCTAssertEqualObjects(commit.prevCID, prevCID, @"Prev CID should match");
}

- (void)testCommitSerialization {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    NSData *serialized = [commit serialize];
    
    XCTAssertNotNil(serialized, @"Serialized commit should not be nil");
    XCTAssertGreaterThan(serialized.length, 0, @"Serialized commit should have data");
    
    CBORValue *decoded = [CBORDecoder decode:serialized];
    XCTAssertNotNil(decoded, @"Decoded CBOR should not be nil");
    XCTAssertEqual(decoded.type, CBORTypeMap, @"Decoded CBOR should be a map");
    
    NSDictionary<CBORValue *, CBORValue *> *map = decoded.map;
    XCTAssertNotNil(map, @"Map should not be nil");
    
    CBORValue *didKey = [CBORValue textString:@"did"];
    CBORValue *versionKey = [CBORValue textString:@"version"];
    CBORValue *dataKey = [CBORValue textString:@"data"];
    CBORValue *revKey = [CBORValue textString:@"rev"];
    
    XCTAssertNotNil(map[didKey], @"Should have 'did' field");
    XCTAssertNotNil(map[versionKey], @"Should have 'version' field");
    XCTAssertNotNil(map[dataKey], @"Should have 'data' field");
    XCTAssertNotNil(map[revKey], @"Should have 'rev' field");
    
    CBORValue *sigKey = [CBORValue textString:@"sig"];
    CBORValue *prevKey = [CBORValue textString:@"prev"];
    XCTAssertNil(map[sigKey], @"Should not have 'sig' field in unsigned commit");
    XCTAssertNil(map[prevKey], @"Should not have 'prev' field when nil");
}

- (void)testCommitSerializationWithPrevContainsCIDTag {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    CID *prevCID = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:prevCID];
    NSData *serialized = [commit serialize];
    
    CBORValue *decoded = [CBORDecoder decode:serialized];
    NSDictionary<CBORValue *, CBORValue *> *map = decoded.map;
    
    CBORValue *prevKey = [CBORValue textString:@"prev"];
    XCTAssertNotNil(map[prevKey], @"Should have 'prev' field when set");
    XCTAssertEqual(map[prevKey].type, CBORTypeTag, @"Prev should be a CID tag");
}

- (void)testCommitSigning {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    
    XCTAssertNotNil(keyPair, @"Key pair should be generated");
    XCTAssertNil(error, @"There should be no error generating key pair");
    
    BOOL signedSuccessfully = [commit signWithPrivateKey:keyPair.privateKey error:&error];
    
    XCTAssertTrue(signedSuccessfully, @"Commit should be signed successfully");
    XCTAssertNil(error, @"There should be no error signing");
    XCTAssertNotNil(commit.signature, @"Signature should be set after signing");
    XCTAssertEqual(commit.signature.length, 64, @"Signature should be 64 bytes (R || S)");
}

- (void)testCommitSignatureVerification {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair1 = [secp generateKeyPairWithError:&error];
    Secp256k1KeyPair *keyPair2 = [secp generateKeyPairWithError:&error];
    
    BOOL signedSuccessfully = [commit signWithPrivateKey:keyPair1.privateKey error:&error];
    XCTAssertTrue(signedSuccessfully, @"Commit should be signed");
    
    BOOL verified = [commit verifySignatureWithPublicKey:keyPair1.publicKey error:&error];
    XCTAssertTrue(verified, @"Signature should verify successfully");
    XCTAssertNil(error, @"There should be no error verifying");
}

- (void)testCommitSignatureVerificationFailsWithWrongKey {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair1 = [secp generateKeyPairWithError:&error];
    Secp256k1KeyPair *keyPair2 = [secp generateKeyPairWithError:&error];
    
    [commit signWithPrivateKey:keyPair1.privateKey error:&error];
    
    BOOL verified = [commit verifySignatureWithPublicKey:keyPair2.publicKey error:&error];
    XCTAssertFalse(verified, @"Signature should fail verification with wrong key");
}

- (void)testCommitSignatureVerificationFailsOnTamperedData {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    
    [commit signWithPrivateKey:keyPair.privateKey error:&error];
    
    commit.did = @"did:plc:differentdid";
    
    BOOL verified = [commit verifySignatureWithPublicKey:keyPair.publicKey error:&error];
    XCTAssertFalse(verified, @"Signature should fail verification after tampering");
}

- (void)testCommitVerificationFailsWithoutSignature {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    
    BOOL verified = [commit verifySignatureWithPublicKey:keyPair.publicKey error:&error];
    
    XCTAssertFalse(verified, @"Verification should fail without signature");
    XCTAssertNotNil(error, @"Error should be set when verifying unsigned commit");
}

- (void)testCommitCID {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    
    [commit signWithPrivateKey:keyPair.privateKey error:&error];
    
    CID *commitCID = [commit computeCID];
    XCTAssertNotNil(commitCID, @"Commit CID should be computed");
    XCTAssertNotNil(commitCID.stringValue, @"Commit CID string should be generated");
    XCTAssertTrue([commitCID.stringValue hasPrefix:@"bafyre"], @"Commit CID should be base32 encoded");
}

- (void)testCommitHashIsDeterministic {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit1 = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    RepoCommit *commit2 = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:nil];
    
    NSData *hash1 = [commit1 computeHash];
    NSData *hash2 = [commit2 computeHash];
    
    XCTAssertEqualObjects(hash1, hash2, @"Hash should be deterministic for same commit data");
}

- (void)testCommitHashChangesWithData {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID1 = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    CID *dataCID2 = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    NSString *rev = @"3l66k7pp33p";
    
    RepoCommit *commit1 = [RepoCommit createCommitWithDid:did data:dataCID1 rev:rev prev:nil];
    RepoCommit *commit2 = [RepoCommit createCommitWithDid:did data:dataCID2 rev:rev prev:nil];
    
    NSData *hash1 = [commit1 computeHash];
    NSData *hash2 = [commit2 computeHash];
    
    XCTAssertNotEqualObjects(hash1, hash2, @"Hash should change with different data CID");
}

- (void)testCommitParsingFromCAR {
    NSString *did = @"did:plc:z72ietkcondg5a46mkxsrvpv";
    CID *dataCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    NSString *rev = @"3l66k7pp33p";
    CID *prevCID = [CID cidFromString:@"bafyreifnqrwbk6ffmyaz5qtujqrzf5qmxf7cbxvgzktl4e3gabuxbtatv4"];
    
    RepoCommit *originalCommit = [RepoCommit createCommitWithDid:did data:dataCID rev:rev prev:prevCID];
    
    // Sign the commit
    Secp256k1 *secp = [Secp256k1 shared];
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [secp generateKeyPairWithError:&error];
    [originalCommit signWithPrivateKey:keyPair.privateKey error:&error];
    
    // Serialize to CAR
    NSData *carData = [originalCommit exportCAR];
    XCTAssertNotNil(carData, @"CAR data should be generated");
    
    // Parse back
    RepoCommit *parsedCommit = [RepoCommit fromCARData:carData error:&error];
    
    XCTAssertNotNil(parsedCommit, @"Should parse commit from CAR data");
    XCTAssertNil(error, @"Should parse without error: %@", error.localizedDescription);
    
    if (parsedCommit) {
        XCTAssertEqualObjects(parsedCommit.did, did, @"DID should match");
        XCTAssertEqualObjects(parsedCommit.dataCID, dataCID, @"Data CID should match");
        XCTAssertEqualObjects(parsedCommit.rev, rev, @"Rev should match");
        XCTAssertEqualObjects(parsedCommit.prevCID, prevCID, @"Prev CID should match");
        XCTAssertNotNil(parsedCommit.signature, @"Signature should be present");
        
        // Verify signature on parsed commit
        BOOL verified = [parsedCommit verifySignatureWithPublicKey:keyPair.publicKey error:&error];
        XCTAssertTrue(verified, @"Parsed commit signature should verify");
    }
}

@end
