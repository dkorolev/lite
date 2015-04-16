/*******************************************************************************
 The MIT License (MIT)

 Copyright (c) 2015 Alexander Zolotarev <me@alex.bio> from Minsk, Belarus
                    Dmitry "Dima" Korolev <dmitry.korolev@gmail.com>

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

#import "AppDelegate.h"

#import "Current/Midichlorians.h"

#include "data_dictionary.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [Midichlorians setup:@"http://localhost:8080/" withLaunchOptions:launchOptions];
  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [Midichlorians emit:iOSFocusEvent(false, "applicationWillResignActive")];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [Midichlorians emit:iOSFocusEvent(false, "applicationDidEnterBackground")];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [Midichlorians emit:iOSFocusEvent(true, "applicationWillEnterForeground")];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [Midichlorians emit:iOSFocusEvent(true, "applicationDidBecomeActive")];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [Midichlorians emit:iOSFocusEvent(false, "applicationWillTerminate")];
}

@end
