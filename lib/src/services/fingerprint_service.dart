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
    SmartLinkLogger.debug('Collecting fingerprint...');

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

      SmartLinkLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      SmartLinkLogger.info('📱 APP FINGERPRINT COLLECTED:');
      SmartLinkLogger.info('  deviceId: ${fingerprint.deviceId}');
      SmartLinkLogger.info('  deviceModel: ${fingerprint.deviceModel}');
      SmartLinkLogger.info('  deviceManufacturer: ${fingerprint.deviceManufacturer}');
      SmartLinkLogger.info('  osName: ${fingerprint.osName}');
      SmartLinkLogger.info('  osVersion: ${fingerprint.osVersion}');
      SmartLinkLogger.info('  screenWidth (logical/CSS): ${fingerprint.screenWidth}');
      SmartLinkLogger.info('  screenHeight (logical/CSS): ${fingerprint.screenHeight}');
      SmartLinkLogger.info('  screenDensity: ${fingerprint.screenDensity}');
      SmartLinkLogger.info('  physicalWidth: ${fingerprint.physicalWidth}');
      SmartLinkLogger.info('  physicalHeight: ${fingerprint.physicalHeight}');
      SmartLinkLogger.info('  locale: ${fingerprint.locale}');
      SmartLinkLogger.info('  timezone: ${fingerprint.timezone}');
      SmartLinkLogger.info('  timezoneOffset: ${fingerprint.timezoneOffset}');
      SmartLinkLogger.info('  connectionType: ${fingerprint.connectionType}');
      SmartLinkLogger.info('  appVersion: ${fingerprint.appVersion}');
      SmartLinkLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      SmartLinkLogger.info('📤 JSON being sent to server:');
      SmartLinkLogger.info('${fingerprint.toJson()}');
      SmartLinkLogger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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
