import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'config.dart';
import 'models/deep_link_data.dart';
import 'services/deep_link_handler.dart';
import 'services/deferred_link_service.dart';
import 'services/fingerprint_service.dart';
import 'services/storage_service.dart';
import 'utils/device_info.dart';
import 'utils/logger.dart';

/// Main SDK class for AE-LINK deferred deep linking
///
/// This is a singleton that manages device fingerprinting, deferred link matching,
/// and deep link handling.
class AeLinkSdk {
  static AeLinkSdk? _instance;
  static late AeLinkConfig _config;

  late StorageService _storageService;
  late FingerprintService _fingerprintService;
  late DeferredLinkService _deferredLinkService;
  late DeepLinkHandler _deepLinkHandler;

  DeepLinkData? _lastDeepLink;
  final StreamController<DeepLinkData> _deepLinkStreamController =
      StreamController<DeepLinkData>.broadcast();

  AeLinkSdk._internal();

  /// Get singleton instance
  static AeLinkSdk get _sdkInstance {
    _instance ??= AeLinkSdk._internal();
    return _instance!;
  }

  /// Initialize the SDK with configuration
  ///
  /// Must be called before any other SDK methods.
  /// This will:
  /// 1. Initialize services (storage, fingerprint, API)
  /// 2. Validate API key with the backend
  /// 3. Register this install/launch
  /// 4. Setup deep link listening
  static Future<void> initialize(AeLinkConfig config) async {
    if (!config.validate()) {
      throw ArgumentError('Invalid AeLinkConfig: tenantApiKey is required');
    }

    _config = config;
    final sdk = _sdkInstance;

    AeLinkLogger.init(debug: config.debug);
    AeLinkLogger.info('Initializing AE-LINK SDK');

    try {
      // Initialize storage
      sdk._storageService = StorageService();
      await sdk._storageService.init();

      // Initialize services
      sdk._fingerprintService = FingerprintService(
        storageService: sdk._storageService,
      );
      sdk._deferredLinkService = DeferredLinkService(config: config);
      sdk._deepLinkHandler = DeepLinkHandler();

      // Register this launch with the backend (non-blocking)
      _registerLaunch();

      // Initialize deep link handler if auto handling is enabled
      if (config.autoHandleDeepLinks) {
        await sdk._deepLinkHandler.initialize();
        sdk._deepLinkHandler.onDeepLink.listen((deepLinkData) {
          sdk._lastDeepLink = deepLinkData;
          sdk._deepLinkStreamController.add(deepLinkData);
        });
      }

      AeLinkLogger.info('SDK initialized');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('SDK init failed', e, stackTrace);
      rethrow;
    }
  }

  /// Register this app launch with the backend.
  /// Validates API key, checks package name, tracks install type.
  static Future<void> _registerLaunch() async {
    try {
      final sdk = _sdkInstance;

      // Get device ID (create if first time)
      var deviceId = sdk._storageService.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = await sdk._fingerprintService.getOrCreateDeviceId();
      }

      final isFirstLaunch = await sdk._storageService.isFirstLaunch();
      // Don't mark first launch complete here — let checkDeferredLink handle it

      String? packageName;
      String? appVersion;
      String? buildNumber;
      try {
        packageName = await _getPackageName();
        appVersion = await DeviceInfoHelper.getAppVersion();
        buildNumber = await DeviceInfoHelper.getAppBuildNumber();
      } catch (_) {}

      final body = jsonEncode({
        'deviceId': deviceId,
        'platform': DeviceInfoHelper.getOsName(),
        'packageName': packageName,
        'appVersion': appVersion,
        'appBuildNumber': buildNumber,
        'osVersion': await DeviceInfoHelper.getOsVersion(),
        'deviceModel': await DeviceInfoHelper.getDeviceModel(),
        'deviceManufacturer': await DeviceInfoHelper.getDeviceManufacturer(),
        'locale': DeviceInfoHelper.getLocale(),
        'timezone': DeviceInfoHelper.getTimezone(),
        'isFirstLaunch': isFirstLaunch,
      });

      final response = await http.Client()
          .post(
            Uri.parse('${_config.apiBaseUrl}/api/v1/sdk/init'),
            headers: _config.getHeaders(),
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['data'];

        if (result != null) {
          // Log install type
          final installType = result['installType'] ?? 'unknown';
          AeLinkLogger.info('Launch registered: $installType');

          // Warn if package name doesn't match
          if (result['appValid'] == false && result['appWarning'] != null) {
            AeLinkLogger.warning(result['appWarning']);
          }
        }
      } else if (response.statusCode == 401) {
        AeLinkLogger.error('Invalid API key — check your dashboard Settings');
      } else {
        AeLinkLogger.debug('SDK init API returned ${response.statusCode}');
      }
    } catch (e) {
      // Non-blocking — SDK should work even if init call fails
      AeLinkLogger.debug('SDK init API call failed: $e');
    }
  }

  /// Get app package name / bundle ID
  static Future<String?> _getPackageName() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.packageName;
    } catch (_) {
      return null;
    }
  }

  /// Check if SDK has been initialized
  static bool get isInitialized => _instance != null;

  /// Get stream of deep links (both deferred and direct)
  static Stream<DeepLinkData> get onDeepLink =>
      _sdkInstance._deepLinkStreamController.stream;

  /// Get the last received deep link
  static DeepLinkData? get lastDeepLink => _sdkInstance._lastDeepLink;

  /// Check for deferred deep link on first app launch
  ///
  /// Returns the matched deep link data if found, null otherwise.
  static Future<DeepLinkData?> checkDeferredLink() async {
    final sdk = _sdkInstance;

    try {
      // Check if first launch
      final isFirstLaunch = await sdk._storageService.isFirstLaunch();
      if (!isFirstLaunch) {
        AeLinkLogger.debug('Not first launch, skipping deferred check');
        return null;
      }

      AeLinkLogger.info('Checking for deferred deep link...');

      // Collect device fingerprint
      final fingerprint = await sdk._fingerprintService.collectFingerprint();

      // Match fingerprint against deferred links
      final deferredLink =
          await sdk._deferredLinkService.matchFingerprint(fingerprint);

      if (deferredLink != null) {
        sdk._lastDeepLink = deferredLink;
        sdk._deepLinkStreamController.add(deferredLink);

        await sdk._storageService.setLastDeferredLink(
          jsonEncode(deferredLink.toJson()),
        );
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());

        AeLinkLogger.info(
            'Deferred link matched: ${deferredLink.deferredLinkId}');
        return deferredLink;
      } else {
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());
        AeLinkLogger.info('No deferred link found (organic install)');
        return null;
      }
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error checking deferred link', e, stackTrace);
      return null;
    }
  }

  /// Confirm that a deferred link was shown to the user
  static Future<void> confirmDeepLink(String deferredLinkId) async {
    try {
      await _sdkInstance._deferredLinkService.confirmDeepLink(deferredLinkId);
      AeLinkLogger.info('Deferred link confirmed');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error confirming deferred link', e, stackTrace);
    }
  }

  /// Manually process a deep link URL
  static void processDeepLink(String url) {
    AeLinkLogger.info('Processing deep link: $url');
    _sdkInstance._deepLinkHandler.processDeepLink(url);
  }

  /// Get the device ID for this device
  static String? getDeviceId() {
    return _sdkInstance._storageService.getDeviceId();
  }

  /// Clear all SDK data from storage
  static Future<void> clearAll() async {
    AeLinkLogger.info('Clearing all AE-LINK SDK data');
    await _sdkInstance._storageService.clearAll();
  }

  /// Dispose the SDK and cleanup resources
  static Future<void> dispose() async {
    final sdk = _sdkInstance;
    await sdk._deepLinkHandler.dispose();
    await sdk._deepLinkStreamController.close();
    sdk._deferredLinkService.dispose();
    _instance = null;
    AeLinkLogger.info('SDK disposed');
  }

  /// Force check for deferred deep link (ignores first-launch check)
  static Future<DeepLinkData?> forceCheckDeferredLink() async {
    final sdk = _sdkInstance;

    try {
      final fingerprint = await sdk._fingerprintService.collectFingerprint();
      final deferredLink =
          await sdk._deferredLinkService.matchFingerprint(fingerprint);

      if (deferredLink != null) {
        sdk._lastDeepLink = deferredLink;
        sdk._deepLinkStreamController.add(deferredLink);
        await sdk._storageService.setLastDeferredLink(
          jsonEncode(deferredLink.toJson()),
        );
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());
      }

      return deferredLink;
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error force checking deferred link', e, stackTrace);
      return null;
    }
  }
}
