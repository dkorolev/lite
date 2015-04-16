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
    mutable std::string device_id;
    void SetDeviceId(const std::string& did) const {
        device_id = did;
    }
    
    template <class A>
    void serialize(A& ar) {
        ar(CEREAL_NVP(device_id));
    }
    
    virtual std::string EventAsString(const std::string& device_id) const {
        SetDeviceId(device_id);
        return JSON(WithBaseType<MidichloriansEvent>(*this));
    }
};

// A helper macro to define structured events.

#ifdef CURRENT_EVENT
#error "The `CURRENT_EVENT` macro should not be defined."
#endif

#define CURRENT_EVENT(M_EVENT_CLASS_NAME, M_IMMEDIATE_BASE)         \
struct M_EVENT_CLASS_NAME;                                  \
CEREAL_REGISTER_TYPE(M_EVENT_CLASS_NAME);                   \
struct M_EVENT_CLASS_NAME##Helper : M_IMMEDIATE_BASE {    \
typedef MidichloriansEvent CEREAL_BASE_TYPE;              \
typedef M_IMMEDIATE_BASE SUPER;                           \
virtual std::string EventAsString(const std::string& device_id) const override {      \
SetDeviceId(device_id); \
return JSON(WithBaseType<MidichloriansEvent>(*this));   \
}                                                         \
template <class A>                                        \
void serialize(A& ar) {                                   \
SUPER::serialize(ar);                                   \
}                                                         \
};                                                          \
struct M_EVENT_CLASS_NAME : M_EVENT_CLASS_NAME##Helper

// Generic iOS events.

CURRENT_EVENT(iOSEvent, MidichloriansEvent) {
    std::string description;
    template<typename A> void serialize(A& ar) {
        SUPER::serialize(ar);
        ar(CEREAL_NVP(description));
    }
    iOSEvent() = default;
    iOSEvent(const std::string& d) : description(d) {}
};

CURRENT_EVENT(iOSAppLaunchEvent, iOSEvent) {
    std::string cf_version;
    uint64_t app_install_time;
    uint64_t app_update_time;
    template<typename A> void serialize(A& ar) {
        SUPER::serialize(ar);
        ar(CEREAL_NVP(cf_version), CEREAL_NVP(app_install_time), CEREAL_NVP(app_update_time));
    }
    iOSAppLaunchEvent() = default;
    iOSAppLaunchEvent(const std::string& cf_version, uint64_t app_install_time, uint64_t app_update_time) : cf_version(cf_version), app_install_time(app_install_time), app_update_time(app_update_time) {
        description = "*FinishLaunchingWithOptions";
    }
};

CURRENT_EVENT(iOSFocusEvent, iOSEvent) {
    bool activated;  // True if gained focus, false if lost focus.
    template<typename A> void serialize(A& ar) {
        SUPER::serialize(ar);
        ar(CEREAL_NVP(activated));
    }
    iOSFocusEvent() = default;
    iOSFocusEvent(bool a, const std::string& d) {
        description = d;
        activated = a;
    }
};

@interface Midichlorians : NSObject

// To be called in application:didFinishLaunchingWithOptions:
// or in application:willFinishLaunchingWithOptions:
+ (void)setup:(NSString *)serverUrl withLaunchOptions:(NSDictionary *)options;

// Emits the event.
+ (void)emit:(const MidichloriansEvent&) event;

@end

#endif  // CURRENT_MIDICHLORIANS_H
