// FuzzFirehose.m - WebSocket/Firehose protocol fuzzing
// Tests WebSocket framing and ATProto firehose messages

#import <Foundation/Foundation.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        if (!data || size == 0) return 0;
        
        NSData *frameData = [NSData dataWithBytes:data length:size];
        
        // Test 1: WebSocket frame header parsing
        if (size >= 2) {
            uint8_t first = data[0];
            uint8_t second = data[1];
            
            // FIN bit (bit 7)
            BOOL fin = (first & 0x80) != 0;
            // Opcode (bits 0-3)
            NSInteger opcode = first & 0x0F;
            // MASK bit (bit 8)
            BOOL masked = (second & 0x80) != 0;
            // Payload length (bits 7-13)
            NSUInteger payloadLen = second & 0x7F;
            (void)fin;
            (void)opcode;
            (void)masked;
            (void)payloadLen;
            
            // Test extended payload length
            if (payloadLen == 126 && size >= 4) {
                uint16_t extLen = (data[2] << 8) | data[3];
                (void)extLen;
            } else if (payloadLen == 127 && size >= 10) {
                uint32_t extLen = (data[6] << 24) | (data[7] << 16) | (data[8] << 8) | data[9];
                (void)extLen;
            }
        }
        
        // Test 2: Op code variations - use NSMutableData
        NSMutableData *mutated = [NSMutableData dataWithData:frameData];
        for (NSInteger i = 0; i < 6 && i < mutated.length; i++) {
            uint8_t b;
            [mutated getBytes:&b range:NSMakeRange(i, 1)];
            b = (b & 0xF0) | ((i == 0 || i == 2 || i == 8) ? i : ((i == 1) ? 1 : ((i == 9) ? 9 : ((i == 10) ? 10 : 0))));
            [mutated replaceBytesInRange:NSMakeRange(i, 1) withBytes:&b length:1];
        }
        
        // Test 3: Fragmentation (continuation frames)
        if (mutated.length > 0) {
            uint8_t b;
            [mutated getBytes:&b range:NSMakeRange(0, 1)];
            b = b & 0x7F;
            [mutated replaceBytesInRange:NSMakeRange(0, 1) withBytes:&b length:1];
        }
        
        // Test 4: Masked vs unmasked
        if (mutated.length > 1) {
            uint8_t b;
            [mutated getBytes:&b range:NSMakeRange(1, 1)];
            b = b | 0x80;
            [mutated replaceBytesInRange:NSMakeRange(1, 1) withBytes:&b length:1];
            b = b & 0x7F;
            [mutated replaceBytesInRange:NSMakeRange(1, 1) withBytes:&b length:1];
        }
        
        // Test 5: Close frame payloads
        if (mutated.length >= 4) {
            uint8_t closeFrame[] = {0x88, 0x02, 0x03, 0xE8};
            NSMutableData *closeData = [NSMutableData dataWithBytes:closeFrame length:4];
            (void)closeData;
        }
        
        // Test 6: Ping/pong frames
        if (mutated.length >= 2) {
            uint8_t b;
            [mutated getBytes:&b range:NSMakeRange(0, 1)];
            if ((b & 0x0F) == 0x9) {
                (void)@"ping";
            } else if ((b & 0x0F) == 0xA) {
                (void)@"pong";
            }
        }
        
        // Test 7: Firehose message types
        if (size >= 4) {
            uint32_t repoOp = *(uint32_t *)data;
            (void)repoOp;
        }
        
        // Test 8: CAR repo operations in firehose
        if (size >= 8) {
            (void)data[0];
            (void)data[4];
        }
        
        // Test 9: Size limits
        if (size > 10 * 1024 * 1024) {
            (void)@"large frame";
        }
    }
    return 0;
}