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

#ifndef C5T_IOS_LOCATION_H
#define C5T_IOS_LOCATION_H

#include <string>
#include <sstream>
#include <iomanip>
#include <exception>

// #error "I've tested this header compiles on 4/10/15. Now let's comment it out for now. - @dkorolev."

namespace alohalytics_lite {

// TODO(dkorolev): This class should be moved away to a separate header file.
// I just want to keep the things as compact as possible for now.
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

  uint64_t timestamp_ms_;  // Milliseconds from January 1, 1970.
  double latitude_deg_;    // Positive degrees from the true North.
  double longitude_deg_;
  double horizontal_accuracy_m_;
  double altitude_m_;
  double vertical_accuracy_m_;
  double bearing_deg_;
  double speed_mps_;  // Meters per second.

  // Use degrees with precision of 7 decimal places - approximately 2cm on Earth.
  static constexpr double TEN_MILLION = 10000000.0;

  // Some params below can be stored with 2 decimal places precision.
  static constexpr double ONE_HUNDRED = 100.0;

  // Compacts location into the byte representation.
  std::string Encode() const {
    std::string s;
    s.push_back(valid_values_mask_);
    if (valid_values_mask_ & HAS_LATLON) {
      static_assert(sizeof(timestamp_ms_) == 8, "Must be uint64_t.");
      // Crop the timestamp from 8 bytes to 6 to save space.
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

  // Production-ready JSON serialization using Cereal.
  template <class A>
  void save(A &ar) const {
    ar(Encode());
  }

  template <class A>
  void load(A &ar) {
    std::string encoded_location;
    ar(encoded_location);
    Decode(encoded_location);
  }

  // Development-friendly serialization for debugging purposes.
  std::string ToDebugString() const {
    std::ostringstream s;
    s << '<' << std::fixed;
    if (valid_values_mask_ & HAS_LATLON) {
      s << "utc=" << timestamp_ms_ << ",lat=" << std::setprecision(7) << latitude_deg_
        << ",lon=" << std::setprecision(7) << longitude_deg_ << ",acc=" << std::setprecision(2)
        << horizontal_accuracy_m_;
    }
    if (valid_values_mask_ & HAS_ALTITUDE) {
      s << ",alt=" << std::setprecision(2) << altitude_m_ << ",vac=" << std::setprecision(2)
        << vertical_accuracy_m_;
    }
    if (valid_values_mask_ & HAS_BEARING) {
      s << ",bea=" << std::setprecision(7) << bearing_deg_;
    }
    if (valid_values_mask_ & HAS_SPEED) {
      s << ",spd=" << std::setprecision(2) << speed_mps_;
    }
    if (valid_values_mask_ & HAS_SOURCE) {
      s << ",src=";
      switch (source_) {
        case Source::GPS:
          s << "GPS";
          break;
        case Source::NETWORK:
          s << "Net";
          break;
        case Source::PASSIVE:
          s << "Psv";
          break;
        default:
          s << "Unk";
          break;
      }
    }
    s << '>';
    return s.str();
  }

 private:
  // Internal, for serialization.
  template <typename T>
  static inline void AppendToStringAsBinary(std::string &str, const T &value, size_t bytes = sizeof(T)) {
    str.append(reinterpret_cast<const char *>(&value), bytes);
  }
};

// Safe extraction from [possible nil] CLLocation to alohalytics_lite::Location.
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

}  // namespace alohalytics_lite

#endif  // C5T_IOS_LOCATION_H
