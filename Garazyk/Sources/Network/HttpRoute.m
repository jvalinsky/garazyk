// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "HttpRoute.h"

@interface ATProtoHttpRoute ()

@property (nonatomic, readwrite, copy) NSString *method;
@property (nonatomic, readwrite, copy) NSString *pattern;
@property (nonatomic, readwrite, copy) HttpRouteHandler handler;
@property (nonatomic, readwrite) NSUInteger priority;

@end

@implementation ATProtoHttpRoute

- (instancetype)initWithMethod:(NSString *)method
                       pattern:(NSString *)pattern
                       handler:(HttpRouteHandler)handler
                      priority:(NSUInteger)priority {
    self = [super init];
    if (self) {
        _method = [method copy];
        _pattern = [pattern copy];
        _handler = [handler copy];
        _priority = priority;
    }
    return self;
}

@end
