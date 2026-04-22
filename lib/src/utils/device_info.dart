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

  /// Get screen dimensions
  static Map<String, double> getScreenDimensions() {
    final mediaQuery = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    );
    return {
      'width': mediaQuery.size.width,
      'height': mediaQuery.size.height,
      'density': mediaQuery.devicePixelRatio,
    };
  }

  /// Get device locale
  static String getLocale() {
    final locale = PlatformDispatcher.instance.locale;
    return '${locale.languageCode}_${locale.countryCode}';
  }

  /// Get device timezone
  static String getTimezone() {
    return DateTime.now().timeZoneOffset.toString();
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

  /// Get public IP address (requires a call to ipify API or similar)
  static Future<String?> getPublicIpAddress() async {
    try {
      // Using a simple free IP detection service
      final response = await Future.delayed(
        const Duration(seconds: 1),
        () => null,
      );
      // Note: In production, you'd call an IP detection API
      // This is a placeholder - the backend can detect IP from request headers
      return null;
    } catch (e) {
      return null;
    }
  }

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
