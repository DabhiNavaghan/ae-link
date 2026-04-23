/// Comprehensive device and app information collected from the host device.
class DeviceInfoResult {
  /// Platform: 'android', 'ios', or 'unknown'
  final String platform;

  // ── Device Identity ──────────────────────────────────────────────────────
  final String? deviceId;
  final String? deviceModel;
  final String? deviceBrand;
  final String? deviceManufacturer;

  /// User-assigned device name (iOS) or device code name (Android)
  final String? deviceName;
  final bool? isPhysicalDevice;

  // ── OS ───────────────────────────────────────────────────────────────────
  final String? osName;
  final String? osVersion;

  // ── Android-specific ─────────────────────────────────────────────────────
  final int? androidSdkLevel;
  final String? androidSecurityPatch;
  final String? androidBuildFingerprint;
  final String? androidHardware;
  final String? androidBoard;
  final String? androidDevice;
  final String? androidProduct;
  final String? androidBuildType;
  final String? androidCodename;
  final String? androidBaseOs;
  final String? androidBootloader;
  final List<String>? supportedAbis;
  final bool? isLowRamDevice;

  // ── Android hardware capabilities (via system features) ──────────────────
  final bool? hasCamera;
  final bool? hasBluetooth;
  final bool? hasNfc;
  final bool? hasFingerprint;
  final bool? hasGps;
  final bool? hasGyroscope;
  final bool? hasAccelerometer;
  final bool? hasWifi;

  // ── iOS-specific ─────────────────────────────────────────────────────────
  final String? iosLocalizedModel;

  /// Hardware identifier e.g. "iPhone14,5"
  final String? iosHardwareIdentifier;
  final String? iosKernelVersion;

  /// True when iOS app is running natively on macOS via Catalyst
  final bool? iosIsAppOnMac;

  // ── App ──────────────────────────────────────────────────────────────────
  final String? appName;
  final String? appVersion;
  final String? appBuildNumber;
  final String? packageName;

  // ── Screen & Display ─────────────────────────────────────────────────────
  /// Physical screen width in pixels
  final double? screenWidth;

  /// Physical screen height in pixels
  final double? screenHeight;

  /// Logical viewport width (screenWidth / devicePixelRatio)
  final double? viewportWidth;

  /// Logical viewport height (screenHeight / devicePixelRatio)
  final double? viewportHeight;
  final double? devicePixelRatio;

  // ── Language & Locale ────────────────────────────────────────────────────
  /// Primary locale, e.g. "en-US"
  final String? locale;

  /// All preferred locales in order, e.g. ["en-US", "fr-FR"]
  final List<String>? preferredLanguages;

  /// IANA timezone name or abbreviation, e.g. "Asia/Kolkata"
  final String? timezone;

  /// UTC offset string, e.g. "+05:30"
  final String? timezoneOffset;

  // ── Network ──────────────────────────────────────────────────────────────
  /// One of: wifi, mobile, ethernet, vpn, bluetooth, other, none
  final String? connectionType;

  // ── Device Capabilities ──────────────────────────────────────────────────
  final int? cpuCores;

  // ── Accessibility ────────────────────────────────────────────────────────
  final double? textScaleFactor;
  final bool? boldText;
  final bool? reduceMotion;
  final bool? highContrast;
  final bool? invertColors;
  final bool? disableAnimations;

  // ── Battery ──────────────────────────────────────────────────────────────
  /// Battery percentage 0–100
  final int? batteryLevel;

  /// One of: charging, discharging, full, connected_not_charging, unknown
  final String? batteryState;
  final bool? isCharging;

  // ── Metadata ─────────────────────────────────────────────────────────────
  final DateTime collectedAt;

  DeviceInfoResult({
    required this.platform,
    required this.collectedAt,
    this.deviceId,
    this.deviceModel,
    this.deviceBrand,
    this.deviceManufacturer,
    this.deviceName,
    this.isPhysicalDevice,
    this.osName,
    this.osVersion,
    this.androidSdkLevel,
    this.androidSecurityPatch,
    this.androidBuildFingerprint,
    this.androidHardware,
    this.androidBoard,
    this.androidDevice,
    this.androidProduct,
    this.androidBuildType,
    this.androidCodename,
    this.androidBaseOs,
    this.androidBootloader,
    this.supportedAbis,
    this.isLowRamDevice,
    this.hasCamera,
    this.hasBluetooth,
    this.hasNfc,
    this.hasFingerprint,
    this.hasGps,
    this.hasGyroscope,
    this.hasAccelerometer,
    this.hasWifi,
    this.iosLocalizedModel,
    this.iosHardwareIdentifier,
    this.iosKernelVersion,
    this.iosIsAppOnMac,
    this.appName,
    this.appVersion,
    this.appBuildNumber,
    this.packageName,
    this.screenWidth,
    this.screenHeight,
    this.viewportWidth,
    this.viewportHeight,
    this.devicePixelRatio,
    this.locale,
    this.preferredLanguages,
    this.timezone,
    this.timezoneOffset,
    this.connectionType,
    this.cpuCores,
    this.textScaleFactor,
    this.boldText,
    this.reduceMotion,
    this.highContrast,
    this.invertColors,
    this.disableAnimations,
    this.batteryLevel,
    this.batteryState,
    this.isCharging,
  });

  /// Flat map suitable for sending to an API or logging.
  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'collectedAt': collectedAt.toIso8601String(),
      'device': {
        'id': deviceId,
        'model': deviceModel,
        'brand': deviceBrand,
        'manufacturer': deviceManufacturer,
        'name': deviceName,
        'isPhysicalDevice': isPhysicalDevice,
      },
      'os': {
        'name': osName,
        'version': osVersion,
      },
      if (platform == 'android')
        'android': {
          'sdkLevel': androidSdkLevel,
          'securityPatch': androidSecurityPatch,
          'buildFingerprint': androidBuildFingerprint,
          'hardware': androidHardware,
          'board': androidBoard,
          'device': androidDevice,
          'product': androidProduct,
          'buildType': androidBuildType,
          'codename': androidCodename,
          'baseOs': androidBaseOs,
          'bootloader': androidBootloader,
          'supportedAbis': supportedAbis,
          'isLowRamDevice': isLowRamDevice,
        },
      if (platform == 'ios')
        'ios': {
          'localizedModel': iosLocalizedModel,
          'hardwareIdentifier': iosHardwareIdentifier,
          'kernelVersion': iosKernelVersion,
          'isAppOnMac': iosIsAppOnMac,
        },
      'app': {
        'name': appName,
        'version': appVersion,
        'buildNumber': appBuildNumber,
        'packageName': packageName,
      },
      'screen': {
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
        'viewportWidth': viewportWidth,
        'viewportHeight': viewportHeight,
        'devicePixelRatio': devicePixelRatio,
      },
      'locale': {
        'primary': locale,
        'preferred': preferredLanguages,
        'timezone': timezone,
        'timezoneOffset': timezoneOffset,
      },
      'network': {
        'connectionType': connectionType,
      },
      'capabilities': {
        'cpuCores': cpuCores,
        'hasCamera': hasCamera,
        'hasBluetooth': hasBluetooth,
        'hasNfc': hasNfc,
        'hasFingerprint': hasFingerprint,
        'hasGps': hasGps,
        'hasGyroscope': hasGyroscope,
        'hasAccelerometer': hasAccelerometer,
        'hasWifi': hasWifi,
      },
      'accessibility': {
        'textScaleFactor': textScaleFactor,
        'boldText': boldText,
        'reduceMotion': reduceMotion,
        'highContrast': highContrast,
        'invertColors': invertColors,
        'disableAnimations': disableAnimations,
      },
      'battery': {
        'level': batteryLevel,
        'state': batteryState,
        'isCharging': isCharging,
      },
    };
  }

  @override
  String toString() =>
      'DeviceInfoResult(platform: $platform, model: $deviceModel, '
      'os: $osName $osVersion, battery: $batteryLevel%)';
}
