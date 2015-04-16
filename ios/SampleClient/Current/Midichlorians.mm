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

#import "midichlorians.h"

#include <string>
#include <map>
#include <sstream>
#include <iomanip>
#include <utility>
#include <thread>
#include <mutex>
#include <queue>

#include <sys/xattr.h>

#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFURL.h>

#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSURLRequest.h>

#include <TargetConditionals.h>  // For `TARGET_OS_IPHONE`.
#if (TARGET_OS_IPHONE > 0)
// Works for all iOS devices, including iPad.
#import <UIKit/UIDevice.h>
#import <UIKit/UIScreen.h>
#import <UIKit/UIApplication.h>
#import <AdSupport/ASIdentifierManager.h>
#endif  // (TARGET_OS_IPHONE > 0)

namespace midichlorians {

// Conversion from [possible nil] `NSString` to `std::string`.
static std::string UnsafeToStdString(NSString *nsString) {
    if (nsString) {
        return std::string([nsString UTF8String]);
    } else {
        return std::string();
    }
}

    /*
// Additional check if the object can be represented as a string.
static std::string ToStdString(id object) {
    if ([object isKindOfClass:[NSString class]]) {
        return UnsafeToStdString(object);
    } else if ([object isKindOfClass:[NSObject class]]) {
        return UnsafeToStdString(((NSObject *)object).description);
    }
    return "ERROR: `ToStdString()` is being provided with neither NSString nor NSObject-inherited object.";
}

// Safe conversion from [possible nil] NSDictionary.
static std::map<std::string, std::string> ToStringMap(NSDictionary *nsDictionary) {
    std::map<std::string, std::string> map;
    for (NSString *key in nsDictionary) {
        map[UnsafeToStdString(key)] = ToStdString([nsDictionary objectForKey:key]);
    }
    return map;
}

// Safe conversion from [possible nil] NSArray.
static std::map<std::string, std::string> ToStringMap(NSArray *nsArray) {
    std::map<std::string, std::string> map;
    std::string key;
    for (id item in nsArray) {
        if (key.empty()) {
            key = ToStdString(item);
            map[key] = "";
        } else {
            map[key] = ToStdString(item);
            key.clear();
        }
    }
    return map;
}
     */

    /*

     */
// Returns a string representing uint64_t timestamp of given file or directory.
// Uses modification date in Unix epoch milliseconds, if available.
static uint64_t PathTimestampMillis(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (attributes) {
        NSDate *date = [attributes objectForKey:NSFileModificationDate];
        return static_cast<uint64_t>([date timeIntervalSince1970] * 1000);
    } else {
        return 0ull;
    }
}

// Returns <unique id, true if it's the very-first app launch>.
static std::pair<std::string, bool> InstallationId() {
    const auto key = @"MidichloriansInstallationId";
    bool firstLaunch = false;
    NSUserDefaults *userDataBase = [NSUserDefaults standardUserDefaults];
    NSString *installationId = [userDataBase objectForKey:key];
    if (installationId == nil) {
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        installationId = [@"iOS:"
                          stringByAppendingString:(NSString *)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, uuid))];
        CFRelease(uuid);
        [userDataBase setValue:installationId forKey:key];
        [userDataBase synchronize];
        firstLaunch = true;
    }
    return std::make_pair([installationId UTF8String], firstLaunch);
}

/*
 #if (TARGET_OS_IPHONE > 0)
 static std::map<std::string, std::string> ParseLaunchOptions(NSDictionary * options) {
 std::map<std::string, std::string> parsed;
 
 NSURL * url = [options objectForKey:UIApplicationLaunchOptionsURLKey];
 if (url) {
 parsed.emplace("UIApplicationLaunchOptionsURLKey", UnsafeToStdString([url absoluteString]));
 }
 NSString * source = [options objectForKey:UIApplicationLaunchOptionsSourceApplicationKey];
 if (source) {
 parsed.emplace("UIApplicationLaunchOptionsSourceApplicationKey", UnsafeToStdString(source));
 }
 return parsed;
 }
 #endif  // (TARGET_OS_IPHONE > 0)
 */

static std::string RectToString(CGRect const &rect) {
    return std::to_string(static_cast<int>(rect.origin.x)) + " " +
    std::to_string(static_cast<int>(rect.origin.y)) + " " +
    std::to_string(static_cast<int>(rect.size.width)) + " " +
    std::to_string(static_cast<int>(rect.size.height));
}
    
    /*
struct AsStringImpl {
    static std::string Invoke(const std::string& s) {
        return s;
    }
    static std::string Invoke(const std::map<std::string, std::string>& m) {
        std::string s;
        bool first = true;
        for (const auto& kv : m) {
            if (first) {
                first = false;
            } else {
                s += ',';
            }
            s += kv.first + '=' + kv.second;
        }
        return s;
    }
};

template<typename T> std::string AsString(T&& s) {
    return AsStringImpl::Invoke(s);
}
     */

namespace consumer {
    namespace thread_unsafe {
        
        class NSLog {
        public:
            void OnMessage(const std::string& message) {
                ::NSLog(@"LogEvent: %s", message.c_str());
            }
        };
        
        class POSTviaHTTP {
        public:
            void SetServerUrl(const std::string& server_url) {
                server_url_ = server_url;
            }
            
            void SetDeviceId(const std::string& device_id) {
                device_id_ = device_id;
            }
            
            const std::string& GetDeviceId() const {
                return device_id_;
            }
            
            void OnMessage(const std::string& message) {
                if (!server_url_.empty()) {
                    ::NSLog(@"LogEvent HTTP: `%s`", message.c_str());
                    
                    const std::string url = "http://localhost:8686/log";
                    
                    NSMutableURLRequest * req =
                    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]]];
                    // TODO(dkorolev): Add this line. I can't deal with its syntax. Objective-C is killing me.                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
                    
                    req.HTTPMethod = @"POST";
                    req.HTTPBody = [NSData dataWithBytes:message.data() length:message.length()];
                    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
                    
                    NSHTTPURLResponse * res = nil;
                    NSError * err = nil;
                    NSData * url_data = [NSURLConnection sendSynchronousRequest:req returningResponse:&res error:&err];
                    
                    // TODO(dkorolev): A bit more detailed error handling.
                    // TODO(dkorolev): If the message queue is persistent, consider keeping unsent entries within it.
                    static_cast<void>(url_data);
                    if (!res) {
                        ::NSLog(@"LogEvent HTTP: Fail.");
                    } else {
                        ::NSLog(@"LogEvent HTTP: OK.");
                    }
                } else {
                    ::NSLog(@"LogEvent HTTP: No `server_url_` set.");
                }
            }
        private:
            std::string server_url_;
            std::string device_id_;
        };
    }
    
    // A straightforward implementation for wrapping calls from multiple sources into a single thread,
    // preserving the order.
    // NOTE: In production, a more advanced implementation should be used,
    // with more efficient in-memory message queue and with optionally persistent storage of events.
    template<class T_SINGLE_THREADED_IMPL> class SimplestThreadSafeWrapper : public T_SINGLE_THREADED_IMPL {
    public:
        SimplestThreadSafeWrapper() : up_(true), thread_(&SimplestThreadSafeWrapper::Thread, this) {
        }
        ~SimplestThreadSafeWrapper() {
            {
                std::unique_lock<std::mutex> lock(mutex_);
                up_ = false;
            }
            cv_.notify_all();
            thread_.join();
        }
        void OnMessage(const std::string& message) {
            {
                std::unique_lock<std::mutex> lock(mutex_);
                queue_.push_back(message);
            }
            cv_.notify_all();
        }
        
    private:
        void Thread() {
            std::string message;
            while (true) {
                // Mutex-locked section: Retrieve the next message, or wait for one.
                {
                    std::unique_lock<std::mutex> lock(mutex_);
                    if (!up_) {
                        // Terminating.
                        return;
                    }
                    if (queue_.empty()) {
                        cv_.wait(lock);
                        continue;
                    } else {
                        message = queue_.front();
                        queue_.pop_front();
                    }
                }
                // Mutex-free section: Process this message.
                T_SINGLE_THREADED_IMPL::OnMessage(message);
            }
        }
        
        std::atomic_bool up_;
        std::deque<std::string> queue_;
        std::condition_variable cv_;
        std::mutex mutex_;
        std::thread thread_;
    };
    
    template<typename T> using ThreadSafeWrapper = SimplestThreadSafeWrapper<T>;
    
    using NSLog = ThreadSafeWrapper<thread_unsafe::NSLog>;
    using POSTviaHTTP = ThreadSafeWrapper<thread_unsafe::POSTviaHTTP>;
    
}  // namespace consumer

template<typename T> struct Singleton {
    static T& Instance() {
        static T instance;
        return instance;
    }
};

using Stats = consumer::POSTviaHTTP;

} // namespace midichlorians

@implementation Midichlorians

using namespace midichlorians;

+ (void)setup:(NSString *)serverUrl withLaunchOptions:(NSDictionary *)options {
    const auto installationId = InstallationId();

    Stats& instance = Singleton<Stats>::Instance();
    
    instance.SetServerUrl([serverUrl UTF8String]);
    instance.SetDeviceId(installationId.first);
    
    // Documents folder modification time can be interpreted as "app install time".
    // App bundle modification time can be interpreted as "app update time".

    if (installationId.second) {
        [Midichlorians emit:iOSEvent("firstLaunch")];
    }
    
    [Midichlorians emit:iOSAppLaunchEvent([[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] UTF8String],
                                          PathTimestampMillis([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                                                                                NSUserDomainMask, YES) firstObject]),
                                          PathTimestampMillis([[NSBundle mainBundle] executablePath]))
                                          ];
    
#if (TARGET_OS_IPHONE > 0)
     UIDevice *device = [UIDevice currentDevice];
     UIScreen *screen = [UIScreen mainScreen];
     std::string preferredLanguages;
     for (NSString *lang in [NSLocale preferredLanguages]) {
     preferredLanguages += [lang UTF8String] + std::string(" ");
     }
     std::string preferredLocalizations;
     for (NSString *loc in [[NSBundle mainBundle] preferredLocalizations]) {
     preferredLocalizations += [loc UTF8String] + std::string(" ");
     }
     NSLocale *locale = [NSLocale currentLocale];
     std::string userInterfaceIdiom = "phone";
     if (device.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
     userInterfaceIdiom = "pad";
     } else if (device.userInterfaceIdiom == UIUserInterfaceIdiomUnspecified) {
     userInterfaceIdiom = "unspecified";
     }
     std::map<std::string, std::string> info = {
     {"deviceName", UnsafeToStdString(device.name)},
     {"deviceSystemName", UnsafeToStdString(device.systemName)},
     {"deviceSystemVersion", UnsafeToStdString(device.systemVersion)},
     {"deviceModel", UnsafeToStdString(device.model)},
     {"deviceUserInterfaceIdiom", userInterfaceIdiom},
     {"screens", std::to_string([UIScreen screens].count)},
     {"screenBounds", RectToString(screen.bounds)},
     {"screenScale", std::to_string(screen.scale)},
     {"preferredLanguages", preferredLanguages},
     {"preferredLocalizations", preferredLocalizations},
     {"localeIdentifier", UnsafeToStdString([locale objectForKey:NSLocaleIdentifier])},
     {"calendarIdentifier", UnsafeToStdString([[locale objectForKey:NSLocaleCalendar] calendarIdentifier])},
     {"localeMeasurementSystem", UnsafeToStdString([locale objectForKey:NSLocaleMeasurementSystem])},
     {"localeDecimalSeparator", UnsafeToStdString([locale objectForKey:NSLocaleDecimalSeparator])},
     };
     if (device.systemVersion.floatValue >= 8.0) {
     info.emplace("screenNativeBounds", RectToString(screen.nativeBounds));
     info.emplace("screenNativeScale", std::to_string(screen.nativeScale));
     }

     if (NSClassFromString(@"ASIdentifierManager")) {
     ASIdentifierManager *manager = [ASIdentifierManager sharedManager];
     info.emplace("isAdvertisingTrackingEnabled", manager.isAdvertisingTrackingEnabled ? "YES" : "NO");
     if (manager.advertisingIdentifier) {
     info.emplace("advertisingIdentifier", UnsafeToStdString(manager.advertisingIdentifier.UUIDString));
     }
     }

     if (!info.empty()) {
         [Midichlorians emit:iOSDeviceInfo(info)];
     }
#endif  // (TARGET_OS_IPHONE > 0)
}

+ (void)emit:(const MidichloriansEvent &)event {
    Stats& instance = Singleton<Stats>::Instance();
    instance.OnMessage(event.EventAsString(instance.GetDeviceId()));  // UnsafeToStdString(event));
}

@end
