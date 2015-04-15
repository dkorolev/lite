/*******************************************************************************
 The MIT License (MIT)
 
 Copyright (c) 2015:
 
 * Dmitry "Dima" Korolev <dmitry.korolev@gmail.com>
 * Alexander Zolotarev <me@alex.bio> from Minsk, Belarus
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 *******************************************************************************/

#ifndef CURRENT_MIDICHLORIANS_H
#define CURRENT_MIDICHLORIANS_H
 
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface Midichlorians : NSObject

// Should be called in application:didFinishLaunchingWithOptions:
// or in application:willFinishLaunchingWithOptions:
+ (void)setup:(NSString *)serverUrl withLaunchOptions:(NSDictionary *)options;

// Alternative to the previous setup method when not using automatic detection 
// of whether the application is being launched for the first time.
+ (void)setup:(NSString *)serverUrl andFirstLaunch:(BOOL)isFirstLaunch withLaunchOptions:(NSDictionary *)options;

// Various logging methods.
+ (void)logEvent:(NSString *)event;
+ (void)logEvent:(NSString *)event withValue:(NSString *)value;
+ (void)logEvent:(NSString *)event withKeyValueArray:(NSArray *)array;
+ (void)logEvent:(NSString *)event withDictionary:(NSDictionary *)dictionary;

@end

#endif  // CURRENT_MIDICHLORIANS_H
