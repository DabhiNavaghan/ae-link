import 'package:uuid/uuid.dart';
import '../models/device_fingerprint.dart';
import '../utils/device_info.dart';
import '../utils/logger.dart';
import 'storage_service.dart';

/// Service for collecting and managing device fingerprints
class FingerprintService {
  final StorageService _storageService;

  FingerprintService({required StorageService storageService})
      : _storageService = storageService;

  /// Collect device fingerprint
  Future<DeviceFingerprint> collectFingerprint() async {
    SmartLinkLogger.verbose('Collecting fingerprint...');
    final stopwatch = Stopwatch()..start();

    try {
      // Get or create device ID
      var deviceId = _storageService.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = const Uuid().v4();
        await _storageService.setDeviceId(deviceId);
      }

      final screenDimensions = DeviceInfoHelper.getScreenDimensions();

      final fingerprint = DeviceFingerprint(
        deviceId: deviceId,
        deviceModel: await DeviceInfoHelper.getDeviceModel(),
        deviceManufacturer: await DeviceInfoHelper.getDeviceManufacturer(),
        osVersion: await DeviceInfoHelper.getOsVersion(),
        osName: DeviceInfoHelper.getOsName(),
        screenWidth: screenDimensions['width'],
        screenHeight: screenDimensions['height'],
        screenDensity: screenDimensions['density'],
        physicalWidth: screenDimensions['physicalWidth'],
        physicalHeight: screenDimensions['physicalHeight'],
        locale: DeviceInfoHelper.getLocale(),
        timezone: DeviceInfoHelper.getTimezone(),
        timezoneOffset: DeviceInfoHelper.getTimezoneOffset(),
        connectionType: await DeviceInfoHelper.getConnectionType(),
        appVersion: await DeviceInfoHelper.getAppVersion(),
        appBuildNumber: await DeviceInfoHelper.getAppBuildNumber(),
        collectedAt: DateTime.now(),
      );

      stopwatch.stop();
      SmartLinkLogger.timing('fingerprint_collect', stopwatch.elapsed);
      SmartLinkLogger.data('fingerprint', {
        'deviceId': fingerprint.deviceId,
        'deviceModel': fingerprint.deviceModel,
        'deviceManufacturer': fingerprint.deviceManufacturer,
        'osName': fingerprint.osName,
        'osVersion': fingerprint.osVersion,
        'screenWidth': fingerprint.screenWidth,
        'screenHeight': fingerprint.screenHeight,
        'screenDensity': fingerprint.screenDensity,
        'physicalWidth': fingerprint.physicalWidth,
        'physicalHeight': fingerprint.physicalHeight,
        'locale': fingerprint.locale,
        'timezone': fingerprint.timezone,
        'timezoneOffset': fingerprint.timezoneOffset,
        'connectionType': fingerprint.connectionType,
        'appVersion': fingerprint.appVersion,
      });
      return fingerprint;
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
        'Error collecting device fingerprint',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Get stored device ID
  String? getStoredDeviceId() {
    return _storageService.getDeviceId();
  }

  /// Create or retrieve device ID
  Future<String> getOrCreateDeviceId() async {
    var deviceId = _storageService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _storageService.setDeviceId(deviceId);
    }
    return deviceId;
  }
}
