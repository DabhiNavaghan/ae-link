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
/// Singleton that manages device fingerprinting, deferred link matching,
/// and deep link handling.
class AeLinkSdk {
  static AeLinkSdk? _instance;
  static late AeLinkConfig _config;
  static bool _validated = false;

  late StorageService _storageService;
  late FingerprintService _fingerprintService;
  late DeferredLinkService _deferredLinkService;
  late DeepLinkHandler _deepLinkHandler;

  DeepLinkData? _lastDeepLink;
  final StreamController<DeepLinkData> _deepLinkStreamController =
      StreamController<DeepLinkData>.broadcast();

  AeLinkSdk._internal();

  static AeLinkSdk get _sdkInstance {
    _instance ??= AeLinkSdk._internal();
    return _instance!;
  }

  /// Initialize the SDK with configuration.
  ///
  /// This will:
  /// 1. Validate the API key with the backend (blocks if invalid)
  /// 2. Check app package/bundle ID against registered apps
  /// 3. Register this install/launch
  /// 4. Setup deep link listening
  ///
  /// Throws [AeLinkInitException] if the API key is invalid.
  static Future<void> initialize(AeLinkConfig config) async {
    if (!config.validate()) {
      throw ArgumentError('Invalid AeLinkConfig: tenantApiKey is required');
    }

    _config = config;
    _validated = false;
    final sdk = _sdkInstance;

    AeLinkLogger.init(debug: config.debug);
    AeLinkLogger.info('Initializing AE-LINK SDK...');

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

      // If adding SDK to an existing app with existing users,
      // mark first launch as done so we don't try deferred linking for them
      if (config.isExistingUser) {
        final prefs = sdk._storageService;
        // Check raw value — isFirstLaunch() would mark it as done
        final alreadyMarked = prefs.getDeviceId() != null;
        if (!alreadyMarked) {
          await prefs.markFirstLaunchComplete();
          AeLinkLogger.info('Existing user — will skip deferred link check');
        }
      }

      // ── STEP 1: Validate API key + register launch (BLOCKING) ──
      await _validateAndRegister();

      if (!_validated) {
        AeLinkLogger.error(
          '══════════════════════════════════════════════════════════\n'
          '  AE-LINK: Invalid API key!\n'
          '  \n'
          '  Get your API key from the AE-LINK dashboard:\n'
          '  ${config.apiBaseUrl}/dashboard/settings\n'
          '  \n'
          '  Pass it when creating AeLinkService:\n'
          '  AeLinkService(apiKey: "YOUR_KEY", ...)\n'
          '══════════════════════════════════════════════════════════',
        );
        // Don't proceed with deep link setup — key is invalid
        return;
      }

      // ── STEP 2: Setup deep link handler ──
      if (config.autoHandleDeepLinks) {
        await sdk._deepLinkHandler.initialize();
        sdk._deepLinkHandler.onDeepLink.listen((deepLinkData) {
          sdk._lastDeepLink = deepLinkData;
          sdk._deepLinkStreamController.add(deepLinkData);
        });
      }

      AeLinkLogger.info('SDK ready');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('SDK init failed', e, stackTrace);
      rethrow;
    }
  }

  /// Validate API key and register this launch with the backend.
  /// This is BLOCKING — if the key is invalid, we stop everything.
  static Future<void> _validateAndRegister() async {
    final sdk = _sdkInstance;

    try {
      // Collect device info
      var deviceId = sdk._storageService.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = await sdk._fingerprintService.getOrCreateDeviceId();
      }

      final isFirstLaunch = await sdk._storageService.isFirstLaunch();

      String? packageName;
      String? appVersion;
      String? buildNumber;
      try {
        final info = await PackageInfo.fromPlatform();
        packageName = info.packageName;
        appVersion = info.version;
        buildNumber = info.buildNumber;
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
        'isFirstLaunch': isFirstLaunch && !_config.isExistingUser,
        'isExistingUser': _config.isExistingUser,
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
        _validated = true;

        if (result != null) {
          final installType = result['installType'] ?? 'unknown';
          AeLinkLogger.info('Launch: $installType');

          if (result['appValid'] == false && result['appWarning'] != null) {
            AeLinkLogger.warning(
              'App mismatch: ${result['appWarning']}\n'
              'Register your app at: ${_config.apiBaseUrl}/dashboard/apps',
            );
          }
        }
      } else if (response.statusCode == 401) {
        _validated = false;
        // Error message is logged by the caller
      } else if (response.statusCode == 404) {
        // Endpoint doesn't exist — old backend version, skip validation
        _validated = true;
        AeLinkLogger.debug(
            'SDK init endpoint not found — update your backend');
      } else {
        // Server error — don't block the SDK, assume valid
        _validated = true;
        AeLinkLogger.debug('SDK init returned ${response.statusCode}');
      }
    } on TimeoutException {
      // Network timeout — don't block the SDK
      _validated = true;
      AeLinkLogger.debug('SDK init timed out — continuing offline');
    } catch (e) {
      // Network error — don't block the SDK
      _validated = true;
      AeLinkLogger.debug('SDK init failed: $e — continuing offline');
    }
  }

  /// Whether the API key has been validated
  static bool get isValidated => _validated;

  /// Check if SDK has been initialized
  static bool get isInitialized => _instance != null;

  /// Get stream of deep links (both deferred and direct)
  static Stream<DeepLinkData> get onDeepLink =>
      _sdkInstance._deepLinkStreamController.stream;

  /// Get the last received deep link
  static DeepLinkData? get lastDeepLink => _sdkInstance._lastDeepLink;

  /// Check for deferred deep link on first app launch.
  ///
  /// Returns the matched deep link data if found, null otherwise.
  static Future<DeepLinkData?> checkDeferredLink() async {
    if (!_validated) {
      AeLinkLogger.error('Cannot check deferred link — API key is invalid');
      return null;
    }

    final sdk = _sdkInstance;

    try {
      final isFirstLaunch = await sdk._storageService.isFirstLaunch();
      if (!isFirstLaunch) {
        AeLinkLogger.debug('Not first launch, skipping deferred check');
        return null;
      }

      AeLinkLogger.info('Checking for deferred deep link...');

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

        AeLinkLogger.info('Deferred link matched: ${deferredLink.deferredLinkId}');
        return deferredLink;
      } else {
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());
        AeLinkLogger.info('No deferred link (organic install)');
        return null;
      }
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Deferred check failed', e, stackTrace);
      return null;
    }
  }

  /// Confirm that a deferred link was shown to the user
  static Future<void> confirmDeepLink(String deferredLinkId) async {
    if (!_validated) return;
    try {
      await _sdkInstance._deferredLinkService.confirmDeepLink(deferredLinkId);
      AeLinkLogger.info('Deferred link confirmed');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Confirm failed', e, stackTrace);
    }
  }

  /// Manually process a deep link URL
  static void processDeepLink(String url) {
    _sdkInstance._deepLinkHandler.processDeepLink(url);
  }

  /// Get the device ID for this device
  static String? getDeviceId() {
    return _sdkInstance._storageService.getDeviceId();
  }

  /// Clear all SDK data from storage
  static Future<void> clearAll() async {
    await _sdkInstance._storageService.clearAll();
    AeLinkLogger.info('SDK data cleared');
  }

  /// Dispose the SDK and cleanup resources
  static Future<void> dispose() async {
    final sdk = _sdkInstance;
    await sdk._deepLinkHandler.dispose();
    await sdk._deepLinkStreamController.close();
    sdk._deferredLinkService.dispose();
    _instance = null;
  }

  /// Force check for deferred deep link (ignores first-launch check)
  static Future<DeepLinkData?> forceCheckDeferredLink() async {
    if (!_validated) {
      AeLinkLogger.error('Cannot check deferred link — API key is invalid');
      return null;
    }

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
      AeLinkLogger.errorWithStackTrace('Force deferred check failed', e, stackTrace);
      return null;
    }
  }
}
