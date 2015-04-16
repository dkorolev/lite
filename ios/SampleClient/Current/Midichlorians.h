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

#ifndef __cplusplus
#error "This file is a C++ header, and it should be `#include`-d or `#import`-ed from an `.mm`, not an `.m` source file."
#endif

#ifndef CURRENT_MIDICHLORIANS_H
#define CURRENT_MIDICHLORIANS_H

#include <string>

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#include "../../../Bricks/cerealize/cerealize.h"

struct MidichloriansEvent {
    template <class A>
    void serialize(A& ar) {
    }
    virtual std::string EventAsString() const {
        return "<UNDEFINED EVENT>";
    }
};

// A helper macro to define structured events.

#ifdef CURRENT_EVENT
#error "The `CURRENT_EVENT` macro should not be defined."
#endif

#define CURRENT_EVENT(M_EVENT_CLASS_NAME, M_IMMEDIATE_BASE)         \
struct M_EVENT_CLASS_NAME;                                  \
CEREAL_REGISTER_TYPE(M_EVENT_CLASS_NAME);                   \
struct M_EVENT_CLASS_NAME##Helper : MidichloriansEvent {    \
typedef MidichloriansEvent CEREAL_BASE_TYPE;              \
typedef M_IMMEDIATE_BASE SUPER;                           \
virtual std::string EventAsString() const override {      \
return JSON(WithBaseType<MidichloriansEvent>(*this));   \
}                                                         \
template <class A>                                        \
void serialize(A& ar) {                                   \
SUPER::serialize(ar);                                   \
}                                                         \
};                                                          \
struct M_EVENT_CLASS_NAME : M_EVENT_CLASS_NAME##Helper


@interface Midichlorians : NSObject

// To be called in application:didFinishLaunchingWithOptions:
// or in application:willFinishLaunchingWithOptions:
+ (void)setup:(NSString *)serverUrl withLaunchOptions:(NSDictionary *)options;

// Emits the event.
+ (void)emit:(const MidichloriansEvent&) event;

@end

#endif  // CURRENT_MIDICHLORIANS_H
