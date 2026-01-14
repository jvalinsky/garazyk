#import "HttpStreamingBody.h"

static const NSUInteger kDefaultMemoryThreshold = 1024 * 1024;

typedef NS_ENUM(NSInteger, HttpStreamingBodyState) {
    HttpStreamingBodyStateReceiving,
    HttpStreamingBodyStateComplete,
    HttpStreamingBodyStateError
};

@interface HttpStreamingBody ()

@property (nonatomic, assign) NSUInteger memoryThreshold;
@property (nonatomic, assign) HttpStreamingBodyState state;
@property (nonatomic, strong) NSMutableData *memoryBuffer;
@property (nonatomic, strong, nullable) NSString *tempFilePath;
@property (nonatomic, strong, nullable) NSFileHandle *tempFileHandle;
@property (nonatomic, assign) NSUInteger length;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, assign) NSInteger errorCode;

@end

@implementation HttpStreamingBody

- (instancetype)init {
    return [self initWithMemoryThreshold:kDefaultMemoryThreshold];
}

- (instancetype)initWithMemoryThreshold:(NSUInteger)memoryThreshold {
    self = [super init];
    if (self) {
        _memoryThreshold = memoryThreshold;
        _state = HttpStreamingBodyStateReceiving;
        _memoryBuffer = [NSMutableData data];
        _length = 0;
    }
    return self;
}

- (void)dealloc {
    [self reset];
}

- (BOOL)appendData:(NSData *)data error:(NSError **)error {
    if (self.state != HttpStreamingBodyStateReceiving) {
        if (error) {
            *error = [self createError];
        }
        return NO;
    }

    if (!data || data.length == 0) {
        return YES;
    }

    self.length += data.length;

    if (self.tempFilePath) {
        return [self writeToFile:data error:error];
    }

    if (self.memoryBuffer.length + data.length <= self.memoryThreshold) {
        [self.memoryBuffer appendData:data];
        return YES;
    }

    return [self switchToFileStreaming:data error:error];
}

- (BOOL)writeToFile:(NSData *)data error:(NSError **)error {
    NSError *writeError = nil;
    [self.tempFileHandle writeData:data error:&writeError];

    if (writeError) {
        self.state = HttpStreamingBodyStateError;
        self.errorMessage = @"Failed to write to temp file";
        self.errorCode = 500;
        if (error) {
            *error = [self createError];
        }
        return NO;
    }

    return YES;
}

- (BOOL)switchToFileStreaming:(NSData *)data error:(NSError **)error {
    NSString *tempDir = NSTemporaryDirectory();
    if (!tempDir) {
        tempDir = @"/tmp";
    }

    NSString *fileName = [NSString stringWithFormat:@"http_body_%llu.tmp", (unsigned long long)[[NSDate date] timeIntervalSince1970] * 1000000 + arc4random_uniform(1000000)];
    self.tempFilePath = [tempDir stringByAppendingPathComponent:fileName];

    NSError *createError = nil;
    [[NSData data] writeToFile:self.tempFilePath options:NSDataWritingAtomic error:&createError];

    if (createError) {
        self.state = HttpStreamingBodyStateError;
        self.errorMessage = @"Failed to create temp file";
        self.errorCode = 500;
        if (error) {
            *error = [self createError];
        }
        return NO;
    }

    self.tempFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.tempFilePath];
    if (!self.tempFileHandle) {
        self.state = HttpStreamingBodyStateError;
        self.errorMessage = @"Failed to open temp file for writing";
        self.errorCode = 500;
        if (error) {
            *error = [self createError];
        }
        return NO;
    }

    if (self.memoryBuffer.length > 0) {
        if (![self writeToFile:self.memoryBuffer error:error]) {
            return NO;
        }
        self.memoryBuffer = nil;
    }

    return [self writeToFile:data error:error];
}

- (BOOL)finalizeWithError:(NSError **)error {
    if (self.state != HttpStreamingBodyStateReceiving) {
        if (error) {
            *error = [self createError];
        }
        return NO;
    }

    if (self.tempFileHandle) {
        [self.tempFileHandle closeFile];
        self.tempFileHandle = nil;
    }

    self.state = HttpStreamingBodyStateComplete;
    return YES;
}

- (NSData *)data {
    if (self.tempFilePath) {
        return [NSData dataWithContentsOfFile:self.tempFilePath options:0 error:nil];
    }
    return [self.memoryBuffer copy];
}

- (NSString *)filePath {
    return self.tempFilePath;
}

- (BOOL)isComplete {
    return self.state == HttpStreamingBodyStateComplete;
}

- (NSInputStream *)createInputStream {
    if (self.state != HttpStreamingBodyStateComplete) {
        return nil;
    }

    if (self.tempFilePath) {
        return [NSInputStream inputStreamWithFileAtPath:self.tempFilePath];
    }

    NSData *data = [self.memoryBuffer copy];
    return [NSInputStream inputStreamWithData:data];
}

- (void)reset {
    self.state = HttpStreamingBodyStateReceiving;
    self.length = 0;

    if (self.tempFileHandle) {
        [self.tempFileHandle closeFile];
        self.tempFileHandle = nil;
    }

    if (self.tempFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempFilePath error:nil];
        self.tempFilePath = nil;
    }

    self.memoryBuffer = [NSMutableData data];
    self.errorMessage = nil;
    self.errorCode = 0;
}

- (NSError *)createError {
    return [NSError errorWithDomain:@"HttpStreamingBody"
                               code:self.errorCode
                           userInfo:@{NSLocalizedDescriptionKey: self.errorMessage ?: @"Unknown error"}];
}

@end
