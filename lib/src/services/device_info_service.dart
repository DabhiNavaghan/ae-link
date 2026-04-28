import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/device_info_result.dart';
import '../utils/logger.dart';

/// Collects comprehensive device, app, and environment information.
class DeviceInfoService {
  static final _deviceInfo = DeviceInfoPlugin();
  static final _battery = Battery();
  static final _connectivity = Connectivity();

  /// Gather all available device and app info in parallel.
  ///
  /// Never throws — every collection group is independently guarded.
  static Future<DeviceInfoResult> getDeviceInfo() async {
    SmartLinkLogger.verbose('Collecting full device info...');

    final results = await Future.wait<Map<String, dynamic>>([
      _collectPlatformData(),
      _collectPackageData(),
      _collectBatteryData(),
      _collectConnectivityData(),
    ]);

    final platform = results[0];
    final package = results[1];
    final battery = results[2];
    final network = results[3];

    final screen = _collectScreenData();
    final locale = _collectLocaleData();
    final accessibility = _collectAccessibilityData();

    return DeviceInfoResult(
      platform: Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : 'unknown',
      collectedAt: DateTime.now(),

      // Device identity
      deviceId: platform['deviceId'] as String?,
      deviceModel: platform['deviceModel'] as String?,
      deviceBrand: platform['deviceBrand'] as String?,
      deviceManufacturer: platform['deviceManufacturer'] as String?,
      deviceName: platform['deviceName'] as String?,
      isPhysicalDevice: platform['isPhysicalDevice'] as bool?,

      // OS
      osName: platform['osName'] as String?,
      osVersion: platform['osVersion'] as String?,

      // Android
      androidSdkLevel: platform['androidSdkLevel'] as int?,
      androidSecurityPatch: platform['androidSecurityPatch'] as String?,
      androidBuildFingerprint: platform['androidBuildFingerprint'] as String?,
      androidHardware: platform['androidHardware'] as String?,
      androidBoard: platform['androidBoard'] as String?,
      androidDevice: platform['androidDevice'] as String?,
      androidProduct: platform['androidProduct'] as String?,
      androidBuildType: platform['androidBuildType'] as String?,
      androidCodename: platform['androidCodename'] as String?,
      androidBaseOs: platform['androidBaseOs'] as String?,
      androidBootloader: platform['androidBootloader'] as String?,
      supportedAbis: (platform['supportedAbis'] as List?)?.cast<String>(),
      isLowRamDevice: platform['isLowRamDevice'] as bool?,

      // Hardware capabilities
      hasCamera: platform['hasCamera'] as bool?,
      hasBluetooth: platform['hasBluetooth'] as bool?,
      hasNfc: platform['hasNfc'] as bool?,
      hasFingerprint: platform['hasFingerprint'] as bool?,
      hasGps: platform['hasGps'] as bool?,
      hasGyroscope: platform['hasGyroscope'] as bool?,
      hasAccelerometer: platform['hasAccelerometer'] as bool?,
      hasWifi: platform['hasWifi'] as bool?,

      // iOS
      iosLocalizedModel: platform['iosLocalizedModel'] as String?,
      iosHardwareIdentifier: platform['iosHardwareIdentifier'] as String?,
      iosKernelVersion: platform['iosKernelVersion'] as String?,
      iosIsAppOnMac: platform['iosIsAppOnMac'] as bool?,

      // App
      appName: package['appName'] as String?,
      appVersion: package['appVersion'] as String?,
      appBuildNumber: package['appBuildNumber'] as String?,
      packageName: package['packageName'] as String?,

      // Screen
      screenWidth: screen['screenWidth'] as double?,
      screenHeight: screen['screenHeight'] as double?,
      viewportWidth: screen['viewportWidth'] as double?,
      viewportHeight: screen['viewportHeight'] as double?,
      devicePixelRatio: screen['devicePixelRatio'] as double?,

      // Locale
      locale: locale['locale'] as String?,
      preferredLanguages:
          (locale['preferredLanguages'] as List?)?.cast<String>(),
      timezone: locale['timezone'] as String?,
      timezoneOffset: locale['timezoneOffset'] as String?,

      // Network
      connectionType: network['connectionType'] as String?,

      // CPU (dart:io — always available)
      cpuCores: Platform.numberOfProcessors,

      // Accessibility
      textScaleFactor: accessibility['textScaleFactor'] as double?,
      boldText: accessibility['boldText'] as bool?,
      reduceMotion: accessibility['reduceMotion'] as bool?,
      highContrast: accessibility['highContrast'] as bool?,
      invertColors: accessibility['invertColors'] as bool?,
      disableAnimations: accessibility['disableAnimations'] as bool?,

      // Battery
      batteryLevel: battery['batteryLevel'] as int?,
      batteryState: battery['batteryState'] as String?,
      isCharging: battery['isCharging'] as bool?,
    );
  }

  // ── Private collectors ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collectPlatformData() async {
    final data = <String, dynamic>{};
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        data['deviceId'] = info.id;
        data['deviceModel'] = info.model;
        data['deviceBrand'] = info.brand;
        data['deviceManufacturer'] = info.manufacturer;
        data['deviceName'] = info.device;
        data['isPhysicalDevice'] = info.isPhysicalDevice;
        data['osName'] = 'android';
        data['osVersion'] = info.version.release;
        data['androidSdkLevel'] = info.version.sdkInt;
        data['androidSecurityPatch'] = info.version.securityPatch;
        data['androidBuildFingerprint'] = info.fingerprint;
        data['androidHardware'] = info.hardware;
        data['androidBoard'] = info.board;
        data['androidDevice'] = info.device;
        data['androidProduct'] = info.product;
        data['androidBuildType'] = info.type;
        data['androidCodename'] = info.version.codename;
        data['androidBaseOs'] = info.version.baseOS;
        data['androidBootloader'] = info.bootloader;
        data['supportedAbis'] = info.supportedAbis;
        data['isLowRamDevice'] = info.isLowRamDevice;

        final features = info.systemFeatures;
        data['hasCamera'] =
            features.contains('android.hardware.camera') ||
            features.contains('android.hardware.camera.any');
        data['hasBluetooth'] =
            features.contains('android.hardware.bluetooth');
        data['hasNfc'] = features.contains('android.hardware.nfc');
        data['hasFingerprint'] =
            features.contains('android.hardware.fingerprint');
        data['hasGps'] =
            features.contains('android.hardware.location.gps');
        data['hasGyroscope'] =
            features.contains('android.hardware.sensor.gyroscope');
        data['hasAccelerometer'] =
            features.contains('android.hardware.sensor.accelerometer');
        data['hasWifi'] = features.contains('android.hardware.wifi');
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        data['deviceId'] = info.identifierForVendor;
        data['deviceModel'] = info.model;
        data['deviceBrand'] = 'Apple';
        data['deviceManufacturer'] = 'Apple';
        data['deviceName'] = info.name;
        data['isPhysicalDevice'] = info.isPhysicalDevice;
        data['osName'] = 'ios';
        data['osVersion'] = info.systemVersion;
        data['iosLocalizedModel'] = info.localizedModel;
        data['iosHardwareIdentifier'] = info.utsname.machine;
        data['iosKernelVersion'] = info.utsname.version;
        data['iosIsAppOnMac'] = info.isiOSAppOnMac;
      }
    } catch (e) {
      SmartLinkLogger.verbose('Platform data error: $e');
    }
    return data;
  }

  static Future<Map<String, dynamic>> _collectPackageData() async {
    final data = <String, dynamic>{};
    try {
      final info = await PackageInfo.fromPlatform();
      data['appName'] = info.appName;
      data['appVersion'] = info.version;
      data['appBuildNumber'] = info.buildNumber;
      data['packageName'] = info.packageName;
    } catch (e) {
      SmartLinkLogger.verbose('Package data error: $e');
    }
    return data;
  }

  static Future<Map<String, dynamic>> _collectBatteryData() async {
    final data = <String, dynamic>{};
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      data['batteryLevel'] = level;
      data['batteryState'] = _batteryStateLabel(state);
      data['isCharging'] =
          state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      SmartLinkLogger.verbose('Battery data error: $e');
    }
    return data;
  }

  static Future<Map<String, dynamic>> _collectConnectivityData() async {
    final data = <String, dynamic>{};
    try {
      final results = await _connectivity.checkConnectivity();
      data['connectionType'] = _connectivityLabel(results);
    } catch (e) {
      SmartLinkLogger.verbose('Connectivity data error: $e');
    }
    return data;
  }

  static Map<String, dynamic> _collectScreenData() {
    final data = <String, dynamic>{};
    try {
      final view =
          WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize;
      final dpr = view.devicePixelRatio;
      data['screenWidth'] = size.width;
      data['screenHeight'] = size.height;
      data['viewportWidth'] = size.width / dpr;
      data['viewportHeight'] = size.height / dpr;
      data['devicePixelRatio'] = dpr;
    } catch (e) {
      SmartLinkLogger.verbose('Screen data error: $e');
    }
    return data;
  }

  static Map<String, dynamic> _collectLocaleData() {
    final data = <String, dynamic>{};
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final primary = dispatcher.locale;
      data['locale'] =
          '${primary.languageCode}-${primary.countryCode ?? ''}';
      data['preferredLanguages'] = dispatcher.locales
          .map((l) => '${l.languageCode}-${l.countryCode ?? ''}')
          .toList();

      final now = DateTime.now();
      data['timezone'] = now.timeZoneName;
      final offset = now.timeZoneOffset;
      final hh = offset.inHours.abs().toString().padLeft(2, '0');
      final mm =
          (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      data['timezoneOffset'] = '${offset.isNegative ? '-' : '+'}$hh:$mm';
    } catch (e) {
      SmartLinkLogger.verbose('Locale data error: $e');
    }
    return data;
  }

  static Map<String, dynamic> _collectAccessibilityData() {
    final data = <String, dynamic>{};
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      data['textScaleFactor'] = dispatcher.textScaleFactor;
      final f = dispatcher.accessibilityFeatures;
      data['boldText'] = f.boldText;
      data['reduceMotion'] = f.reduceMotion;
      data['highContrast'] = f.highContrast;
      data['invertColors'] = f.invertColors;
      data['disableAnimations'] = f.disableAnimations;
    } catch (e) {
      SmartLinkLogger.verbose('Accessibility data error: $e');
    }
    return data;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _batteryStateLabel(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return 'charging';
      case BatteryState.discharging:
        return 'discharging';
      case BatteryState.full:
        return 'full';
      case BatteryState.connectedNotCharging:
        return 'connected_not_charging';
      case BatteryState.unknown:
        return 'unknown';
    }
  }

  static String _connectivityLabel(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return 'wifi';
    if (results.contains(ConnectivityResult.mobile)) return 'mobile';
    if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    if (results.contains(ConnectivityResult.vpn)) return 'vpn';
    if (results.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
    if (results.contains(ConnectivityResult.other)) return 'other';
    return 'none';
  }
}
