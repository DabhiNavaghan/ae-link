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
    AeLinkLogger.info('Collecting device fingerprint');

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
        locale: DeviceInfoHelper.getLocale(),
        timezone: DeviceInfoHelper.getTimezone(),
        connectionType: await DeviceInfoHelper.getConnectionType(),
        appVersion: await DeviceInfoHelper.getAppVersion(),
        appBuildNumber: await DeviceInfoHelper.getAppBuildNumber(),
        collectedAt: DateTime.now(),
      );

      AeLinkLogger.debug('Device fingerprint collected: $fingerprint');
      return fingerprint;
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
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
