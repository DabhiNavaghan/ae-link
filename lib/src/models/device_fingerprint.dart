/// Device fingerprint data collected for deferred link matching
class DeviceFingerprint {
  /// Device IP address
  final String? ipAddress;

  /// Device model name (e.g., 'SM-G950F')
  final String? deviceModel;

  /// Device manufacturer (e.g., 'Samsung')
  final String? deviceManufacturer;

  /// Android ID or iOS IDFV
  final String? deviceId;

  /// Operating system version
  final String? osVersion;

  /// Operating system (android or ios)
  final String? osName;

  /// Screen width in physical pixels (matches browser's window.screen.width)
  final double? screenWidth;

  /// Screen height in physical pixels (matches browser's window.screen.height)
  final double? screenHeight;

  /// Screen density / DPI
  final double? screenDensity;

  /// Device locale in browser format (e.g., 'en-US')
  final String? locale;

  /// Device timezone name (IANA format, e.g., 'Asia/Kolkata')
  final String? timezone;

  /// Device timezone offset (e.g., '+05:30')
  final String? timezoneOffset;

  /// Connection type (wifi, mobile, none, bluetooth)
  final String? connectionType;

  /// App version
  final String? appVersion;

  /// App build number
  final String? appBuildNumber;

  /// Timestamp when fingerprint was collected
  final DateTime? collectedAt;

  /// Additional custom fingerprint data
  final Map<String, dynamic>? customData;

  DeviceFingerprint({
    this.ipAddress,
    this.deviceModel,
    this.deviceManufacturer,
    this.deviceId,
    this.osVersion,
    this.osName,
    this.screenWidth,
    this.screenHeight,
    this.screenDensity,
    this.locale,
    this.timezone,
    this.timezoneOffset,
    this.connectionType,
    this.appVersion,
    this.appBuildNumber,
    this.collectedAt,
    this.customData,
  });

  /// Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'ip_address': ipAddress,
      'device_model': deviceModel,
      'device_manufacturer': deviceManufacturer,
      'device_id': deviceId,
      'os_version': osVersion,
      'os_name': osName,
      'screen_width': screenWidth,
      'screen_height': screenHeight,
      'screen_density': screenDensity,
      'locale': locale,
      'timezone': timezone,
      'timezone_offset': timezoneOffset,
      'connection_type': connectionType,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'collected_at': collectedAt?.toIso8601String(),
      if (customData != null) ...customData!,
    };
  }

  /// Create from JSON response
  factory DeviceFingerprint.fromJson(Map<String, dynamic> json) {
    return DeviceFingerprint(
      ipAddress: json['ip_address'] as String?,
      deviceModel: json['device_model'] as String?,
      deviceManufacturer: json['device_manufacturer'] as String?,
      deviceId: json['device_id'] as String?,
      osVersion: json['os_version'] as String?,
      osName: json['os_name'] as String?,
      screenWidth: (json['screen_width'] as num?)?.toDouble(),
      screenHeight: (json['screen_height'] as num?)?.toDouble(),
      screenDensity: (json['screen_density'] as num?)?.toDouble(),
      locale: json['locale'] as String?,
      timezone: json['timezone'] as String?,
      timezoneOffset: json['timezone_offset'] as String?,
      connectionType: json['connection_type'] as String?,
      appVersion: json['app_version'] as String?,
      appBuildNumber: json['app_build_number'] as String?,
      collectedAt: json['collected_at'] != null
          ? DateTime.parse(json['collected_at'] as String)
          : null,
    );
  }

  @override
  String toString() =>
      'DeviceFingerprint(deviceModel: $deviceModel, osName: $osName, locale: $locale)';
}
