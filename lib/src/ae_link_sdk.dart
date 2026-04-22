import 'dart:async';
import 'dart:convert';
import 'config.dart';
import 'models/deep_link_data.dart';
import 'services/deep_link_handler.dart';
import 'services/deferred_link_service.dart';
import 'services/fingerprint_service.dart';
import 'services/storage_service.dart';
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
  /// 2. Setup deep link listening
  /// 3. Check for deferred deep link on first launch
  static Future<void> initialize(AeLinkConfig config) async {
    if (!config.validate()) {
      throw ArgumentError('Invalid AeLinkConfig: apiBaseUrl and tenantApiKey are required');
    }

    _config = config;
    final sdk = _sdkInstance;

    AeLinkLogger.init(debug: config.debug);
    AeLinkLogger.info('Initializing AE-LINK SDK');
    AeLinkLogger.debug('Config: $config');

    try {
      // Initialize storage
      sdk._storageService = StorageService();
      await sdk._storageService.init();
      AeLinkLogger.debug('Storage service initialized');

      // Initialize services
      sdk._fingerprintService = FingerprintService(
        storageService: sdk._storageService,
      );
      sdk._deferredLinkService = DeferredLinkService(config: config);
      sdk._deepLinkHandler = DeepLinkHandler();

      // Initialize deep link handler if auto handling is enabled
      if (config.autoHandleDeepLinks) {
        await sdk._deepLinkHandler.initialize();
        sdk._deepLinkHandler.onDeepLink.listen((deepLinkData) {
          sdk._lastDeepLink = deepLinkData;
          sdk._deepLinkStreamController.add(deepLinkData);
        });
      }

      AeLinkLogger.info('AE-LINK SDK initialized successfully');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Failed to initialize AE-LINK SDK', e, stackTrace);
      rethrow;
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
  /// This should be called early in your app's initialization,
  /// typically in main() before runApp().
  ///
  /// Returns the matched deep link data if found, null otherwise.
  static Future<DeepLinkData?> checkDeferredLink() async {
    final sdk = _sdkInstance;

    AeLinkLogger.info('Checking for deferred deep link');

    try {
      // Check if first launch
      final isFirstLaunch = await sdk._storageService.isFirstLaunch();
      if (!isFirstLaunch) {
        AeLinkLogger.debug('Not first launch, skipping deferred link check');
        return null;
      }

      // Collect device fingerprint
      final fingerprint = await sdk._fingerprintService.collectFingerprint();

      // Match fingerprint against deferred links
      final deferredLink = await sdk._deferredLinkService.matchFingerprint(fingerprint);

      if (deferredLink != null) {
        // Store and emit the deferred link
        sdk._lastDeepLink = deferredLink;
        sdk._deepLinkStreamController.add(deferredLink);

        // Cache the result
        await sdk._storageService.setLastDeferredLink(
          jsonEncode(deferredLink.toJson()),
        );
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());

        AeLinkLogger.info('Deferred link found: ${deferredLink.deferredLinkId}');
        return deferredLink;
      } else {
        // Mark that we've checked for deferred links
        await sdk._storageService.setLastDeferredLinkCheckTime(DateTime.now());
        AeLinkLogger.info('No deferred link found');
        return null;
      }
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Error checking deferred link', e, stackTrace);
      return null;
    }
  }

  /// Confirm that a deferred link was shown to the user
  ///
  /// Call this after displaying the deep link content to the user.
  /// This helps AE-LINK track conversions and improve targeting.
  static Future<void> confirmDeepLink(String deferredLinkId) async {
    AeLinkLogger.info('Confirming deferred link: $deferredLinkId');

    try {
      await _sdkInstance._deferredLinkService.confirmDeepLink(deferredLinkId);
      AeLinkLogger.info('Deferred link confirmed');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Error confirming deferred link', e, stackTrace);
    }
  }

  /// Manually process a deep link
  ///
  /// Useful if you're receiving deep links through a custom method
  /// (e.g., push notifications) instead of through app_links.
  static void processDeepLink(String url) {
    AeLinkLogger.info('Processing deep link: $url');
    _sdkInstance._deepLinkHandler.processDeepLink(url);
  }

  /// Get the device ID for this device
  static String? getDeviceId() {
    return _sdkInstance._storageService.getDeviceId();
  }

  /// Clear all SDK data from storage
  ///
  /// This will reset the first launch flag and other cached data.
  static Future<void> clearAll() async {
    AeLinkLogger.info('Clearing all AE-LINK SDK data');
    await _sdkInstance._storageService.clearAll();
  }

  /// Dispose the SDK and cleanup resources
  ///
  /// Call this when your app is shutting down.
  static Future<void> dispose() async {
    AeLinkLogger.info('Disposing AE-LINK SDK');
    final sdk = _sdkInstance;

    await sdk._deepLinkHandler.dispose();
    await sdk._deepLinkStreamController.close();
    sdk._deferredLinkService.dispose();

    _instance = null;
    AeLinkLogger.info('AE-LINK SDK disposed');
  }

  /// Force check for deferred deep link (ignores time threshold)
  ///
  /// Use this to manually trigger a deferred link check.
  static Future<DeepLinkData?> forceCheckDeferredLink() async {
    final sdk = _sdkInstance;

    AeLinkLogger.info('Force checking for deferred deep link');

    try {
      final fingerprint = await sdk._fingerprintService.collectFingerprint();
      final deferredLink = await sdk._deferredLinkService.matchFingerprint(fingerprint);

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
      AeLinkLogger.errorWithStackTrace('Error force checking deferred link', e, stackTrace);
      return null;
    }
  }
}
