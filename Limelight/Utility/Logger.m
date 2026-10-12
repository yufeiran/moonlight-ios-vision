//
//  Logger.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/10/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Logger.h"
#import <TargetConditionals.h>

#if TARGET_OS_VISION
extern void MLRecordClientDiagnostic(const char *message);
#endif

static LogLevel LoggerLogLevel = LOG_I;

void LogTagv(LogLevel level, NSString* tag, NSString* fmt, va_list args);

void Log(LogLevel level, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    LogTagv(level, NULL, fmt, args);
    va_end(args);
}

void LogTag(LogLevel level, NSString* tag, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    LogTagv(level, tag, fmt, args);
    va_end(args);
}

void LogTagv(LogLevel level, NSString* tag, NSString* fmt, va_list args) {
    NSString* levelPrefix = @"";
    
    if (level < LoggerLogLevel) {
        return;
    }
    
    switch(level) {
        case LOG_D:
            levelPrefix = PRFX_DEBUG;
            break;
        case LOG_I:
            levelPrefix = PRFX_INFO;
            break;
        case LOG_W:
            levelPrefix = PRFX_WARN;
            break;
        case LOG_E:
            levelPrefix = PRFX_ERROR;
            break;
        default:
            levelPrefix = @"";
            assert(false);
            break;
    }
    NSString* prefixedString;
    if (tag) {
        prefixedString = [NSString stringWithFormat:@"%@ (%@) %@", levelPrefix, tag, fmt];
    } else {
        prefixedString = [NSString stringWithFormat:@"%@ %@", levelPrefix, fmt];
    }
#if TARGET_OS_VISION
    // NSLog may only reach unified logging when no debugger is attached.
    // Give the local rotating diagnostic writer an independent copy.
    va_list diagnosticArgs;
    va_copy(diagnosticArgs, args);
    NSString *diagnostic = [[NSString alloc] initWithFormat:prefixedString arguments:diagnosticArgs];
    va_end(diagnosticArgs);
    MLRecordClientDiagnostic(diagnostic.UTF8String);
#if !__has_feature(objc_arc)
    [diagnostic release];
#endif
#endif
    NSLogv(prefixedString, args);
}
