// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceLtHash.h"

#import <CommonCrypto/CommonDigest.h>

#include "Vendor/BLAKE3/blake3.h"

NSString *const PDSSpaceLtHashErrorDomain = @"com.garazyk.space.lthash";

enum {
  PDSSpaceLtHashLaneCount = 1024,
  PDSSpaceLtHashStateLength = 2048,
};

@interface PDSSpaceLtHash ()
@property(nonatomic, readwrite, copy) NSData *state;
@end

@implementation PDSSpaceLtHash

- (instancetype)init {
  return [self initWithState:[NSMutableData dataWithLength:PDSSpaceLtHashStateLength]
                       error:nil];
}

- (instancetype)initWithState:(NSData *)state error:(NSError **)error {
  if (state.length != PDSSpaceLtHashStateLength) {
    if (error) {
      *error = [NSError errorWithDomain:PDSSpaceLtHashErrorDomain
                                   code:PDSSpaceLtHashErrorInvalidState
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"LtHash state must be exactly 2048 bytes"}];
    }
    return nil;
  }

  self = [super init];
  if (self) {
    _state = [state copy];
  }
  return self;
}

- (void)addElement:(NSString *)element {
  [self applyElement:element subtract:NO];
}

- (void)removeElement:(NSString *)element {
  [self applyElement:element subtract:YES];
}

- (NSData *)digest {
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(self.state.bytes, (CC_LONG)self.state.length, hash);
  return [NSData dataWithBytes:hash length:sizeof(hash)];
}

- (void)applyElement:(NSString *)element subtract:(BOOL)subtract {
  NSData *input = [(element ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
  uint8_t expanded[PDSSpaceLtHashStateLength];
  blake3_hasher hasher;
  blake3_hasher_init(&hasher);
  blake3_hasher_update(&hasher, input.bytes, input.length);
  blake3_hasher_finalize(&hasher, expanded, sizeof(expanded));

  NSMutableData *updated = [self.state mutableCopy];
  uint8_t *stateBytes = updated.mutableBytes;
  for (NSUInteger lane = 0; lane < PDSSpaceLtHashLaneCount; lane++) {
    NSUInteger offset = lane * 2;
    uint16_t current = (uint16_t)stateBytes[offset] |
                       ((uint16_t)stateBytes[offset + 1] << 8);
    uint16_t contribution = (uint16_t)expanded[offset] |
                            ((uint16_t)expanded[offset + 1] << 8);
    uint16_t result = subtract ? (uint16_t)(current - contribution)
                               : (uint16_t)(current + contribution);
    stateBytes[offset] = (uint8_t)(result & 0xff);
    stateBytes[offset + 1] = (uint8_t)(result >> 8);
  }
  self.state = updated;
}

@end
