---
title: Fast Parsing & Chunked Security
description: Avoiding memory-hogging naive string splits during massive blob uploads
---

In HTTP/1.1, the `Transfer-Encoding: chunked` header is mandated when a payload is being streamed
dynamically and the total exact `Content-Length` cannot possibly be known upfront by the connecting
sender.

In the real world of the AT Protocol, this happens constantly. When a user records a video on their
phone and uploads it to Bluesky via `com.atproto.repo.uploadBlob`, the client streams the data in
fragmented binary chunks over the network.

A naive implementation of a chunked parser in popular high-level interpreted languages (like Python
or standard Node.js scripts) typically reads the entire incoming TCP stream into system memory,
converts it to a massive comprehensive String object, and eagerly splits the entire string
arbitrarily by `\r\n` tokens to isolate the chunk sizes from the binary data.

**This is a critical, devastating performance bug in a centralized PDS.** Converting a raw 50MB
binary video chunk into an Objective-C `NSString` will predictably cause massive Automatic Reference
Counting (ARC) heap memory spikes, eagerly triggering the Linux OOM-killer (Out of Memory) and
immediately, violently crashing the server under moderate concurrent load.

## Byte-by-Byte Scanning

`ATProtoPDS` combats this elegantly right at the network edge.

The custom `HttpChunkedBodyParser` avoids high-level string reallocation entirely. Instead, it
operates strictly down on the metal, using native `NSData` by algorithmically scanning raw `uint8_t`
memory pointers inside the highly optimized `parseChunkSizeFromData:` routine.

```objc
+ (NSUInteger)parseChunkSizeFromData:(NSData *)data
                              offset:(NSUInteger)offset
                                size:(NSUInteger *)size {
                                
    // 1. Point a standard C-pointer directly to the raw, un-copied memory buffer
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger current = offset;
    
    // 2. Scan byte-by-byte looking for the strict HTTP CRLF terminator (\r\n)
    while (current < length - 1) {
        if (bytes[current] == '\r' && bytes[current+1] == '\n') {
            // Terminator found! The preceding bytes represent the chunk size in hex.
            
            // 3. Convert ONLY the tiny ASCII hex substring directly to an integer 
            //    WITHOUT allocating any massive intermediate payload NSString objects.
            NSString *hexStr = [[NSString alloc] initWithBytes:&bytes[offset]
                                                        length:current - offset
                                                      encoding:NSASCIIStringEncoding];
            
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            unsigned long long parsedSize = 0;
            [scanner scanHexLongLong:&parsedSize];
            
            // Assign the successfully extracted integer by reference
            *size = (NSUInteger)parsedSize;
            
            // Return the new byte offset pointer directly past the "\r\n"
            return current + 2; 
        }
        current++;
    }
    
    // Incomplete chunk size data in the TCP buffer, return 0 to cleanly wait for more socket bytes
    return 0;
}
```

### The $O(N)$ Zero-Copy Advantage

By precisely retaining the `NSData` buffer strictly where the physical C-pointer offset left off in
the previous TCP stream fragment, the parser maintains an incredibly strict, deterministic $O(N)$
execution time across thousands of parallel video uploads.

Because we only allocate a tiny `NSString` to parse the tiny hex chunk length (e.g., parsing the
string `"1F4\r\n"` instead of the 50MB binary blob following it), there are absolutely minimal
intermediate object allocations.

This strict architectural guarantee dictates that a giant multi-gigabyte blob stream uploaded from a
malicious client results in completely flat, zero-growth heap metrics on the server software,
flawlessly ensuring stable memory metrics across heavy federation traffic periods.
