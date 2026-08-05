import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Helper class to collect device information
class DeviceInfoHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static final Connectivity _connectivity = Connectivity();

  /// Get device model
  static Future<String?> getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.model;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get device manufacturer
  static Future<String?> getDeviceManufacturer() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.manufacturer;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.systemName; // "iOS"
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get device ID (Android ID or iOS IDFV)
  static Future<String?> getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get OS version
  static Future<String?> getOsVersion() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.systemVersion;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get OS name
  static String getOsName() {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    }
    return 'unknown';
  }

  /// Get screen dimensions for fingerprint matching.
  ///
  /// PHYSICAL pixels are the primary signal. Logical pixels are NOT directly
  /// comparable across browser and app: Chrome reports CSS pixels at its own
  /// device-scale-factor while Flutter reports logical pixels at
  /// [FlutterView.devicePixelRatio], and on most Android devices those two
  /// ratios differ (e.g. a panel that Chrome calls 412x915 Flutter calls
  /// 384x853). Multiplying each side back out by its own ratio lands both on
  /// the panel's real resolution, which always agrees.
  ///
  /// We read [FlutterView.physicalSize] directly rather than
  /// `MediaQueryData.size`, because the latter is derived and reads as zero
  /// before the first frame — the exact moment the SDK collects a fingerprint
  /// on a cold start.
  static Map<String, double> getScreenDimensions() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final dpr = view.devicePixelRatio;
    final physical = view.physicalSize;

    // Guard against a zero-size view (can happen if called before the engine
    // has attached a surface) — fall back to the MediaQuery-derived size.
    var physicalWidth = physical.width;
    var physicalHeight = physical.height;
    if (physicalWidth <= 0 || physicalHeight <= 0) {
      final size = MediaQueryData.fromView(view).size;
      physicalWidth = size.width * dpr;
      physicalHeight = size.height * dpr;
    }

    return {
      // Logical pixels — kept for backwards compatibility and display.
      'width': (physicalWidth / dpr).roundToDouble(),
      'height': (physicalHeight / dpr).roundToDouble(),
      'density': dpr,
      // Physical pixels — the signal the backend actually matches on.
      'physicalWidth': physicalWidth.roundToDouble(),
      'physicalHeight': physicalHeight.roundToDouble(),
    };
  }

  /// Get device locale (matches browser's navigator.language format: "en-US")
  ///
  /// The country code is frequently null on Android. Emitting "en-null" in
  /// that case downgraded an otherwise exact locale match to a partial one,
  /// so a missing region is dropped and the bare language code is sent.
  static String getLocale() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final country = locale.countryCode;
    if (country == null || country.isEmpty) {
      return locale.languageCode;
    }
    // Use hyphen separator to match browser format (navigator.language = "en-US")
    return '${locale.languageCode}-$country';
  }

  /// Get device timezone (IANA name to match browser's Intl.DateTimeFormat)
  ///
  /// Returns the IANA timezone name (e.g., "Asia/Kolkata", "America/New_York")
  /// which matches the browser's Intl.DateTimeFormat().resolvedOptions().timeZone
  static String getTimezone() {
    // DateTime.now().timeZoneName returns the IANA name on most platforms
    // e.g., "IST", "EST", "Asia/Kolkata" depending on platform
    final tzName = DateTime.now().timeZoneName;

    // On some platforms timeZoneName returns abbreviations (IST, EST, PST).
    // We also send the offset so the backend can match either way.
    // The backend's timezone matcher should handle both formats.
    return tzName;
  }

  /// Get timezone offset string (e.g., "+05:30", "-08:00")
  /// Useful as fallback when timeZoneName returns abbreviations
  static String getTimezoneOffset() {
    final offset = DateTime.now().timeZoneOffset;
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return '$sign$hours:$minutes';
  }

  /// Get connection type
  static Future<String?> getConnectionType() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        return 'wifi';
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        return 'mobile';
      } else if (connectivityResult.contains(ConnectivityResult.bluetooth)) {
        return 'bluetooth';
      }
      return 'none';
    } catch (e) {
      return null;
    }
  }

  /// Get app version
  static Future<String?> getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return null;
    }
  }

  /// Get app build number
  static Future<String?> getAppBuildNumber() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.buildNumber;
    } catch (e) {
      return null;
    }
  }

  /// Always returns null — the client does not resolve its own public IP.
  ///
  /// The backend reads the IP from the request headers, which is both cheaper
  /// and harder to spoof than trusting a value the client looked up itself.
  /// Kept so callers compiled against it keep working.
  static Future<String?> getPublicIpAddress() async => null;

  /// Get Android-specific device info
  static Future<Map<String, dynamic>?> getAndroidDeviceInfo() async {
    try {
      if (!Platform.isAndroid) return null;
      final androidInfo = await _deviceInfo.androidInfo;
      return {
        'hardware': androidInfo.hardware,
        'device': androidInfo.device,
        'brand': androidInfo.brand,
        'fingerprint': androidInfo.fingerprint,
        'host': androidInfo.host,
      };
    } catch (e) {
      return null;
    }
  }

  /// Get iOS-specific device info
  static Future<Map<String, dynamic>?> getIosDeviceInfo() async {
    try {
      if (!Platform.isIOS) return null;
      final iosInfo = await _deviceInfo.iosInfo;
      return {
        'name': iosInfo.name,
        'system_name': iosInfo.systemName,
        'is_physical_device': iosInfo.isPhysicalDevice,
      };
    } catch (e) {
      return null;
    }
  }
}
