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

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag."
#endif

#import "alohalytics_objc.h"

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

#include <TargetConditionals.h>  // TARGET_OS_IPHONE
#if (TARGET_OS_IPHONE > 0)
// Works for all iOS devices, including iPad.
#import <UIKit/UIDevice.h>
#import <UIKit/UIScreen.h>
#import <UIKit/UIApplication.h>
#import <AdSupport/ASIdentifierManager.h>
#endif  // TARGET_OS_IPHONE

// using namespace alohalytics;

// namespace {
// Conversion from [possible nil] NSString to std::string.
static std::string ToStdString(NSString *nsString) {
    if (nsString) {
        return std::string([nsString UTF8String]);
    }
    return std::string();
}

// Additional check if object can be represented as a string.
static std::string ToStdStringSafe(id object) {
    if ([object isKindOfClass:[NSString class]]) {
        return ToStdString(object);
    } else if ([object isKindOfClass:[NSObject class]]) {
        return ToStdString(((NSObject *)object).description);
    }
    return "ERROR: Trying to log neither NSString nor NSObject-inherited object.";
}

// Safe conversion from [possible nil] NSDictionary.
static std::map<std::string, std::string> ToStringMap(NSDictionary *nsDictionary) {
    std::map<std::string, std::string> map;
    for (NSString *key in nsDictionary) {
        map[ToStdString(key)] = ToStdStringSafe([nsDictionary objectForKey:key]);
    }
    return map;
}

// Safe conversion from [possible nil] NSArray.
static std::map<std::string, std::string> ToStringMap(NSArray *nsArray) {
    std::map<std::string, std::string> map;
    std::string key;
    for (id item in nsArray) {
        if (key.empty()) {
            key = ToStdStringSafe(item);
            map[key] = "";
        } else {
            map[key] = ToStdStringSafe(item);
            key.clear();
        }
    }
    return map;
}

// Returns string representing uint64_t timestamp of given file or directory.
// Uses modification date in Unix epoch milliseconds, if available.
static std::string PathTimestampMillis(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (attributes) {
        NSDate *date = [attributes objectForKey:NSFileModificationDate];
        return std::to_string(static_cast<uint64_t>([date timeIntervalSince1970] * 1000.0));
    }
    return std::string("0");
}

// Returns <unique id, true if it's the very-first app launch>.
static std::pair<std::string, bool> InstallationId() {
    bool firstLaunch = false;
    NSUserDefaults *userDataBase = [NSUserDefaults standardUserDefaults];
    NSString *installationId = [userDataBase objectForKey:@"AlohalyticsInstallationId"];
    if (installationId == nil) {
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        // All iOS IDs start with I:
        installationId = [@"I:"
                          stringByAppendingString:(NSString *)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, uuid))];
        CFRelease(uuid);
        [userDataBase setValue:installationId forKey:@"AlohalyticsInstallationId"];
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
 parsed.emplace("UIApplicationLaunchOptionsURLKey", ToStdString([url absoluteString]));
 }
 NSString * source = [options objectForKey:UIApplicationLaunchOptionsSourceApplicationKey];
 if (source) {
 parsed.emplace("UIApplicationLaunchOptionsSourceApplicationKey", ToStdString(source));
 }
 return parsed;
 }
 #endif  // TARGET_OS_IPHONE
 */

class Location {
    enum Mask : uint8_t {
        NOT_INITIALIZED = 0,
        HAS_LATLON = 1 << 0,
        HAS_ALTITUDE = 1 << 1,
        HAS_BEARING = 1 << 2,
        HAS_SPEED = 1 << 3,
        HAS_SOURCE = 1 << 4
    } valid_values_mask_ = NOT_INITIALIZED;
    
public:
    class LocationDecodeException : public std::exception {};
    
    // Milliseconds from January 1, 1970.
    uint64_t timestamp_ms_;
    double latitude_deg_;
    double longitude_deg_;
    double horizontal_accuracy_m_;
    double altitude_m_;
    double vertical_accuracy_m_;
    // Positive degrees from the true North.
    double bearing_deg_;
    // Meters per second.
    double speed_mps_;
    
    // We use degrees with precision of 7 decimal places - it's approx 2cm precision on Earth.
    static constexpr double TEN_MILLION = 10000000.0;
    // Some params below can be stored with 2 decimal places precision.
    static constexpr double ONE_HUNDRED = 100.0;
    
    // Compacts location into the byte representation.
    std::string Encode() const {
        std::string s;
        s.push_back(valid_values_mask_);
        if (valid_values_mask_ & HAS_LATLON) {
            static_assert(sizeof(timestamp_ms_) == 8, "We cut off timestamp from 8 bytes to 6 to save space.");
            AppendToStringAsBinary(s, timestamp_ms_, sizeof(timestamp_ms_) - 2);
            const int32_t lat10mil = latitude_deg_ * TEN_MILLION;
            AppendToStringAsBinary(s, lat10mil);
            const int32_t lon10mil = longitude_deg_ * TEN_MILLION;
            AppendToStringAsBinary(s, lon10mil);
            const uint32_t horizontal_accuracy_cm = horizontal_accuracy_m_ * ONE_HUNDRED;
            AppendToStringAsBinary(s, horizontal_accuracy_cm);
            if (valid_values_mask_ & HAS_SOURCE) {
                s.push_back(source_);
            }
        }
        if (valid_values_mask_ & HAS_ALTITUDE) {
            const int32_t altitude_cm = altitude_m_ * ONE_HUNDRED;
            AppendToStringAsBinary(s, altitude_cm);
            const uint16_t vertical_accuracy_cm = vertical_accuracy_m_ * ONE_HUNDRED;
            AppendToStringAsBinary(s, vertical_accuracy_cm);
        }
        if (valid_values_mask_ & HAS_BEARING) {
            const uint32_t bearing10mil = bearing_deg_ * TEN_MILLION;
            AppendToStringAsBinary(s, bearing10mil);
        }
        if (valid_values_mask_ & HAS_SPEED) {
            const uint16_t speedx100mps = speed_mps_ * ONE_HUNDRED;
            AppendToStringAsBinary(s, speedx100mps);
        }
        return s;
    }
    
    // Initializes location from serialized byte array created by ToString() method.
    explicit Location(const std::string &encoded) { Decode(encoded); }
    
    void Decode(const std::string &encoded) {
        if (encoded.empty()) {
            throw LocationDecodeException();
        }
        std::string::size_type i = 0;
        const std::string::size_type size = encoded.size();
        valid_values_mask_ = static_cast<Mask>(encoded[i++]);
        if (valid_values_mask_ & HAS_LATLON) {
            if ((size - i) < 18) {
                throw LocationDecodeException();
            }
            timestamp_ms_ = *reinterpret_cast<const uint32_t *>(&encoded[i]) |
            (static_cast<uint64_t>(*reinterpret_cast<const uint16_t *>(&encoded[i + 4])) << 32);
            i += sizeof(uint64_t) - 2;  // We use 6 bytes to store timestamps.
            latitude_deg_ = *reinterpret_cast<const int32_t *>(&encoded[i]) / TEN_MILLION;
            i += sizeof(int32_t);
            longitude_deg_ = *reinterpret_cast<const int32_t *>(&encoded[i]) / TEN_MILLION;
            i += sizeof(int32_t);
            horizontal_accuracy_m_ = *reinterpret_cast<const uint32_t *>(&encoded[i]) / ONE_HUNDRED;
            i += sizeof(uint32_t);
            if (valid_values_mask_ & HAS_SOURCE) {
                if ((size - i) < 1) {
                    throw LocationDecodeException();
                }
                source_ = static_cast<Source>(encoded[i++]);
            }
        }
        if (valid_values_mask_ & HAS_ALTITUDE) {
            if ((size - i) < 6) {
                throw LocationDecodeException();
            }
            altitude_m_ = *reinterpret_cast<const int32_t *>(&encoded[i]) / ONE_HUNDRED;
            i += sizeof(int32_t);
            vertical_accuracy_m_ = *reinterpret_cast<const uint16_t *>(&encoded[i]) / ONE_HUNDRED;
            i += sizeof(uint16_t);
        }
        if (valid_values_mask_ & HAS_BEARING) {
            if ((size - i) < 4) {
                throw LocationDecodeException();
            }
            bearing_deg_ = *reinterpret_cast<const uint32_t *>(&encoded[i]) / TEN_MILLION;
            i += sizeof(uint32_t);
        }
        if (valid_values_mask_ & HAS_SPEED) {
            if ((size - i) < 2) {
                throw LocationDecodeException();
            }
            speed_mps_ = *reinterpret_cast<const uint16_t *>(&encoded[i]) / ONE_HUNDRED;
            i += sizeof(uint16_t);
        }
    }
    
    Location() = default;
    
    enum Source : std::uint8_t { UNKNOWN = 0, GPS = 1, NETWORK = 2, PASSIVE = 3 } source_;
    
    bool HasLatLon() const { return valid_values_mask_ & HAS_LATLON; }
    Location &SetLatLon(uint64_t timestamp_ms,
                        double latitude_deg,
                        double longitude_deg,
                        double horizontal_accuracy_m) {
        // We do not support values without known horizontal accuracy.
        if (horizontal_accuracy_m > 0.0) {
            timestamp_ms_ = timestamp_ms;
            latitude_deg_ = latitude_deg;
            longitude_deg_ = longitude_deg;
            horizontal_accuracy_m_ = horizontal_accuracy_m;
            valid_values_mask_ = static_cast<Mask>(valid_values_mask_ | HAS_LATLON);
        }
        return *this;
    }
    
    bool HasSource() const { return valid_values_mask_ & HAS_SOURCE; }
    Location &SetSource(Source source) {
        source_ = source;
        valid_values_mask_ = static_cast<Mask>(valid_values_mask_ | HAS_SOURCE);
        return *this;
    }
    
    bool HasAltitude() const { return valid_values_mask_ & HAS_ALTITUDE; }
    Location &SetAltitude(double altitude_m, double vertical_accuracy_m) {
        if (vertical_accuracy_m > 0.0) {
            altitude_m_ = altitude_m;
            vertical_accuracy_m_ = vertical_accuracy_m;
            valid_values_mask_ = static_cast<Mask>(valid_values_mask_ | HAS_ALTITUDE);
        }
        return *this;
    }
    
    bool HasBearing() const { return valid_values_mask_ & HAS_BEARING; }
    Location &SetBearing(double bearing_deg) {
        if (bearing_deg >= 0.0) {
            bearing_deg_ = bearing_deg;
            valid_values_mask_ = static_cast<Mask>(valid_values_mask_ | HAS_BEARING);
        }
        return *this;
    }
    
    bool HasSpeed() const { return valid_values_mask_ & HAS_SPEED; }
    Location &SetSpeed(double speed_mps) {
        if (speed_mps >= 0.0) {
            speed_mps_ = speed_mps;
            valid_values_mask_ = static_cast<Mask>(valid_values_mask_ | HAS_SPEED);
        }
        return *this;
    }
    
    template <class Archive>
    void save(Archive &ar) const {
        ar(Encode());
    }
    
    template <class Archive>
    void load(Archive &ar) {
        std::string encoded_location;
        ar(encoded_location);
        Decode(encoded_location);
    }
    
    std::string ToDebugString() const {
        std::ostringstream stream;
        stream << '<' << std::fixed;
        if (valid_values_mask_ & HAS_LATLON) {
            stream << "utc=" << timestamp_ms_ << ",lat=" << std::setprecision(7) << latitude_deg_
            << ",lon=" << std::setprecision(7) << longitude_deg_ << ",acc=" << std::setprecision(2)
            << horizontal_accuracy_m_;
        }
        if (valid_values_mask_ & HAS_ALTITUDE) {
            stream << ",alt=" << std::setprecision(2) << altitude_m_ << ",vac=" << std::setprecision(2)
            << vertical_accuracy_m_;
        }
        if (valid_values_mask_ & HAS_BEARING) {
            stream << ",bea=" << std::setprecision(7) << bearing_deg_;
        }
        if (valid_values_mask_ & HAS_SPEED) {
            stream << ",spd=" << std::setprecision(2) << speed_mps_;
        }
        if (valid_values_mask_ & HAS_SOURCE) {
            stream << ",src=";
            switch (source_) {
                case Source::GPS:
                    stream << "GPS";
                    break;
                case Source::NETWORK:
                    stream << "Net";
                    break;
                case Source::PASSIVE:
                    stream << "Psv";
                    break;
                default:
                    stream << "Unk";
                    break;
            }
        }
        stream << '>';
        return stream.str();
    }
    
private:
    template <typename T>
    static inline void AppendToStringAsBinary(std::string &str, const T &value, size_t bytes = sizeof(T)) {
        str.append(reinterpret_cast<const char *>(&value), bytes);
    }
};

// } // namespace

@implementation Alohalytics

// Safe extraction from [possible nil] CLLocation to alohalytics::Location.
static Location ExtractLocation(CLLocation *l) {
    Location extracted;
    if (l) {
        // Validity of values is checked according to Apple's documentation:
        // https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CLLocation_Class/
        if (l.horizontalAccuracy >= 0) {
            extracted.SetLatLon([l.timestamp timeIntervalSince1970] * 1000.,
                                l.coordinate.latitude,
                                l.coordinate.longitude,
                                l.horizontalAccuracy);
        }
        if (l.verticalAccuracy >= 0) {
            extracted.SetAltitude(l.altitude, l.verticalAccuracy);
        }
        if (l.speed >= 0) {
            extracted.SetSpeed(l.speed);
        }
        if (l.course >= 0) {
            extracted.SetBearing(l.course);
        }
    }
    return extracted;
}

#if (TARGET_OS_IPHONE > 0)
static std::string RectToString(CGRect const &rect) {
    return std::to_string(static_cast<int>(rect.origin.x)) + " " +
    std::to_string(static_cast<int>(rect.origin.y)) + " " +
    std::to_string(static_cast<int>(rect.size.width)) + " " +
    std::to_string(static_cast<int>(rect.size.height));
}
#endif

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
    static std::string Invoke(const Location& l) {
        return l.ToDebugString();
    }
};

template<typename T> std::string AsString(T&& s) {
    return AsStringImpl::Invoke(s);
}

namespace consumer {
    
    namespace thread_unsafe {
        class NSLog final {
        public:
            void OnMessage(const std::string& message) {
                ::NSLog(@"LogEvent: %s", message.c_str());
            }
        };
        
        class POSTviaHTTP final {
        public:
            void OnMessage(const std::string& message) {
                ::NSLog(@"LogEvent HTTP: %s", message.c_str());
                
                const std::string url = "http://localhost:8686/log";
                const std::string body = message;
                
                // This is Xcode's "neat" indentation format. Don't ask me WTF it is. -- @dkorolev
                NSMutableURLRequest * request =
                [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]]];
                 // TODO(dkorolev): Add this line. I can't deal with its syntax.                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
                
                    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
                
//                if (!user_agent.empty()) {
  //                  [request setValue:[NSString stringWithUTF8String:user_agent.c_str()] forHTTPHeaderField:@"User-Agent"];
                //}
                
                //if (!method.empty()) {
                  //  request.HTTPMethod = [NSString stringWithUTF8String:method.c_str()];
                //}
                                                  
                                                  request.HTTPMethod = @"POST";
                
                    request.HTTPBody = [NSData dataWithBytes:body.data() length:body.length()];
                
                NSHTTPURLResponse * response = nil;
                NSError * err = nil;
                NSData * url_data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&err];
                static_cast<void>(url_data);
                if (!response) {
                    ::NSLog(@"HTTP fail.");
                } else {
                    ::NSLog(@"HTTP OK.");
                }
                
            }
        };
    }
    
    // The simplest possible implementation of wrapping calls from multiple sources into a single processor thread.
    template<class T_SINGLE_THREADED_IMPL> class SimplestThreadSafeWrapper final {
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
                impl_.OnMessage(message);
            }
        }
        
        T_SINGLE_THREADED_IMPL impl_;
        
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

template<class T_CONSUMER> class StatsImpl {
public:
    static StatsImpl &Instance() {
        static StatsImpl stats;
        return stats;
    }
    
    void SetDebugMode(bool enable) {
    }
    
    void InternalLogEvent(const std::string& message) {
        impl_.OnMessage(message);
    }
    
    template<typename P1> void LogEvent(P1&& p1) {
        InternalLogEvent(AsString(std::forward<P1>(p1)));
    }
    
    template<typename P1, typename P2> void LogEvent(P1&& p1, P2&& p2) {
        InternalLogEvent(AsString(std::forward<P1>(p1)) + '\t' + AsString(std::forward<P2>(p2)));
    }
    
    template<typename P1, typename P2, typename P3> void LogEvent(P1&& p1, P2&& p2, P3&& p3) {
        InternalLogEvent(AsString(std::forward<P1>(p1)) + '\t' + AsString(std::forward<P2>(p2)) + '\t' + AsString(std::forward<P3>(p3)));
    }
    
private:
    T_CONSUMER impl_;
};

using Stats = StatsImpl<consumer::POSTviaHTTP>;

#if (TARGET_OS_IPHONE > 0)
// Logs some basic device's info.
static void LogSystemInformation() {
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
    // alohalytics::
    std::map<std::string, std::string> info = {
        {"deviceName", ToStdString(device.name)},
        {"deviceSystemName", ToStdString(device.systemName)},
        {"deviceSystemVersion", ToStdString(device.systemVersion)},
        {"deviceModel", ToStdString(device.model)},
        {"deviceUserInterfaceIdiom", userInterfaceIdiom},
        {"screens", std::to_string([UIScreen screens].count)},
        {"screenBounds", RectToString(screen.bounds)},
        {"screenScale", std::to_string(screen.scale)},
        {"preferredLanguages", preferredLanguages},
        {"preferredLocalizations", preferredLocalizations},
        {"localeIdentifier", ToStdString([locale objectForKey:NSLocaleIdentifier])},
        {"calendarIdentifier", ToStdString([[locale objectForKey:NSLocaleCalendar] calendarIdentifier])},
        {"localeMeasurementSystem", ToStdString([locale objectForKey:NSLocaleMeasurementSystem])},
        {"localeDecimalSeparator", ToStdString([locale objectForKey:NSLocaleDecimalSeparator])},
    };
    if (device.systemVersion.floatValue >= 8.0) {
        info.emplace("screenNativeBounds", RectToString(screen.nativeBounds));
        info.emplace("screenNativeScale", std::to_string(screen.nativeScale));
    }
    Stats &instance = Stats::Instance();
    instance.LogEvent("$iosDeviceInfo", info);
    
    info.clear();
    if (device.systemVersion.floatValue >= 6.0) {
        if (device.identifierForVendor) {
            info.emplace("identifierForVendor", ToStdString(device.identifierForVendor.UUIDString));
        }
        if (NSClassFromString(@"ASIdentifierManager")) {
            ASIdentifierManager *manager = [ASIdentifierManager sharedManager];
            info.emplace("isAdvertisingTrackingEnabled", manager.isAdvertisingTrackingEnabled ? "YES" : "NO");
            if (manager.advertisingIdentifier) {
                info.emplace("advertisingIdentifier", ToStdString(manager.advertisingIdentifier.UUIDString));
            }
        }
    }
    if (!info.empty()) {
        instance.LogEvent("$iosDeviceIds", info);
    }
}
#endif  // TARGET_OS_IPHONE

+ (void)setDebugMode:(BOOL)enable {
    Stats::Instance().SetDebugMode(enable);
}

+ (void)setup:(NSString *)serverUrl withLaunchOptions:(NSDictionary *)options {
    [Alohalytics setup:serverUrl andFirstLaunch:YES withLaunchOptions:options];
}

+ (void)setup:(NSString *)serverUrl
andFirstLaunch:(BOOL)isFirstLaunch
withLaunchOptions:(NSDictionary *)options {
    // TODO(dkorolev): InstallationId and SystemInformation.
    /*
     /// const auto installationId = InstallationId();
     /// Stats & instance = Stats::Instance();
     ///instance.SetClientId(installationId.first)
     ///   .SetServerUrl([serverUrl UTF8String])
     ///        .SetStoragePath(StoragePath());
     
     // Calculate some basic statistics about installations/updates/launches.
     NSUserDefaults * userDataBase = [NSUserDefaults standardUserDefaults];
     NSString * installedVersion = [userDataBase objectForKey:@"AlohalyticsInstalledVersion"];
     bool forceUpload = false;
     if (installationId.second && isFirstLaunch && installedVersion == nil) {
     NSString * version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
     // Documents folder modification time can be interpreted as a "first app launch time" or an approx. "app
     install time".
     // App bundle modification time can be interpreted as an "app update time".
     instance.LogEvent("$install", {{"CFBundleShortVersionString", [version UTF8String]},
     {"documentsTimestampMillis", PathTimestampMillis([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
     NSUserDomainMask, YES) firstObject])},
     {"bundleTimestampMillis", PathTimestampMillis([[NSBundle mainBundle] executablePath])}});
     [userDataBase setValue:version forKey:@"AlohalyticsInstalledVersion"];
     [userDataBase synchronize];
     #if (TARGET_OS_IPHONE > 0)
     LogSystemInformation();
     #else
     static_cast<void>(options);  // Unused variable warning fix.
     #endif  // TARGET_OS_IPHONE
     forceUpload = true;
     } else {
     NSString * version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
     if (installedVersion == nil || ![installedVersion isEqualToString:version]) {
     instance.LogEvent("$update", {{"CFBundleShortVersionString", [version UTF8String]},
     {"documentsTimestampMillis",
     PathTimestampMillis([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
     firstObject])},
     {"bundleTimestampMillis", PathTimestampMillis([[NSBundle mainBundle] executablePath])}});
     [userDataBase setValue:version forKey:@"AlohalyticsInstalledVersion"];
     [userDataBase synchronize];
     #if (TARGET_OS_IPHONE > 0)
     LogSystemInformation();
     #endif  // TARGET_OS_IPHONE
     forceUpload = true;
     }
     }
     instance.LogEvent("$launch"
     #if (TARGET_OS_IPHONE > 0)
     , ParseLaunchOptions(options)
     #endif  // TARGET_OS_IPHONE
     );
     // Force uploading to get first-time install information before uninstall.
     if (forceUpload) {
     instance.Upload();
     }
     */
}

+ (void)logEvent:(NSString *)event {
    Stats::Instance().LogEvent(ToStdString(event));
}

+ (void)logEvent:(NSString *)event atLocation:(CLLocation *)location {
    Stats::Instance().LogEvent(ToStdString(event), ExtractLocation(location));
}

+ (void)logEvent:(NSString *)event withValue:(NSString *)value {
    Stats::Instance().LogEvent(ToStdString(event), ToStdString(value));
}

+ (void)logEvent:(NSString *)event withValue:(NSString *)value atLocation:(CLLocation *)location {
    Stats::Instance().LogEvent(ToStdString(event), ToStdString(value), ExtractLocation(location));
}

+ (void)logEvent:(NSString *)event withKeyValueArray:(NSArray *)array {
    Stats::Instance().LogEvent(ToStdString(event), ToStringMap(array));
}

+ (void)logEvent:(NSString *)event withKeyValueArray:(NSArray *)array atLocation:(CLLocation *)location {
    Stats::Instance().LogEvent(ToStdString(event), ToStringMap(array), ExtractLocation(location));
}

+ (void)logEvent:(NSString *)event withDictionary:(NSDictionary *)dictionary {
    Stats::Instance().LogEvent(ToStdString(event), ToStringMap(dictionary));
}

+ (void)logEvent:(NSString *)event withDictionary:(NSDictionary *)dictionary atLocation:(CLLocation *)location {
    Stats::Instance().LogEvent(ToStdString(event), ToStringMap(dictionary), ExtractLocation(location));
}

@end
