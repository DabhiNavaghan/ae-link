import 'dart:async';
import 'package:flutter/material.dart';
import 'ae_link_sdk.dart';
import 'config.dart';
import 'models/deep_link_data.dart';
import 'models/device_info_result.dart';

/// Callback type for handling deep links
typedef DeepLinkCallback = void Function(DeepLinkData data);

/// Callback type for handling errors
typedef ErrorCallback = void Function(String message, dynamic error);

/// AeLinkService — single entry point for all SmartLink functionality.
///
/// Handles SDK initialization, deferred deep link checking, deep link
/// listening, and cleanup. Use this instead of calling AeLinkSdk directly.
///
/// Usage in main.dart:
/// ```dart
/// final aeLink = AeLinkService(
///   apiKey: 'your-api-key',
///   onDeepLink: (data) {
///     // Navigate based on data.eventId, data.action, etc.
///   },
/// );
/// await aeLink.initialize();
/// ```
class AeLinkService {
  /// Backend API base URL (defaults to https://aelink.vercel.app)
  final String apiBaseUrl;

  /// Tenant API key from the SmartLink dashboard
  final String apiKey;

  /// Called when a deep link is received (both deferred and direct)
  final DeepLinkCallback onDeepLink;

  /// Called when an error occurs (optional)
  final ErrorCallback? onError;

  /// Enable debug logging
  final bool debug;

  /// API request timeout in seconds
  final int timeoutSeconds;

  /// Auto-listen for Universal Links / App Links
  final bool autoHandleDeepLinks;

  /// Set to true when adding SmartLink to an app that already has users.
  /// This prevents existing users from being treated as new installs
  /// and skips deferred link checking for them.
  ///
  /// Example: set based on whether the user is logged in:
  /// ```dart
  /// AeLinkService(
  ///   apiKey: 'KEY',
  ///   isExistingUser: authService.isLoggedIn,
  ///   onDeepLink: (data) { ... },
  /// )
  /// ```
  final bool isExistingUser;

  StreamSubscription<DeepLinkData>? _deepLinkSubscription;
  bool _initialized = false;

  AeLinkService({
    this.apiBaseUrl = kAeLinkDefaultBaseUrl,
    required this.apiKey,
    required this.onDeepLink,
    this.onError,
    this.debug = false,
    this.timeoutSeconds = 30,
    this.autoHandleDeepLinks = true,
    this.isExistingUser = false,
  });

  /// Initialize the SDK, check for deferred deep links, and start listening.
  ///
  /// Call this once in your main() before runApp(), or in your app's
  /// initial state. This does everything:
  ///
  /// 1. Initializes the SmartLink SDK
  /// 2. Checks for deferred deep links (first launch after install)
  /// 3. Starts listening for incoming app links
  ///
  /// Returns the deferred [DeepLinkData] if found on first launch, null otherwise.
  Future<DeepLinkData?> initialize() async {
    if (_initialized) return null;

    try {
      // 1. Initialize SDK
      await AeLinkSdk.initialize(
        AeLinkConfig(
          apiBaseUrl: apiBaseUrl,
          tenantApiKey: apiKey,
          debug: debug,
          requestTimeoutSeconds: timeoutSeconds,
          autoHandleDeepLinks: autoHandleDeepLinks,
          isExistingUser: isExistingUser,
        ),
      );

      // 2. Listen for deep links (deferred + direct)
      _deepLinkSubscription = AeLinkSdk.onDeepLink.listen(
        (data) {
          onDeepLink(data);

          // Auto-confirm deferred links
          if (data.isDeferred && data.deferredLinkId != null) {
            AeLinkSdk.confirmDeepLink(data.deferredLinkId!);
          }
        },
        onError: (error) {
          onError?.call('Deep link stream error', error);
        },
      );

      // 3. Check for deferred deep link on first launch
      final deferredLink = await AeLinkSdk.checkDeferredLink();

      _initialized = true;

      return deferredLink;
    } catch (e) {
      onError?.call('SmartLink initialization failed', e);
      return null;
    }
  }

  /// Manually process a deep link URL (e.g., from a push notification)
  void handleUrl(String url) {
    AeLinkSdk.processDeepLink(url);
  }

  /// Force check for deferred deep link (ignores first-launch check)
  Future<DeepLinkData?> forceCheckDeferred() async {
    try {
      return await AeLinkSdk.forceCheckDeferredLink();
    } catch (e) {
      onError?.call('Force deferred check failed', e);
      return null;
    }
  }

  /// Get the device ID assigned by the SDK
  String? get deviceId => AeLinkSdk.getDeviceId();

  /// Collect comprehensive device, app, and environment information.
  ///
  /// Returns a [DeviceInfoResult] with platform, OS, screen, locale,
  /// network, battery, hardware capabilities, and accessibility data.
  Future<DeviceInfoResult> getDeviceInfo() => AeLinkSdk.getDeviceInfo();

  /// Whether the SDK has been initialized
  bool get isInitialized => _initialized;

  /// Get the last received deep link
  DeepLinkData? get lastDeepLink => AeLinkSdk.lastDeepLink;

  /// Cleanup — call in your app's dispose
  Future<void> dispose() async {
    await _deepLinkSubscription?.cancel();
    await AeLinkSdk.dispose();
    _initialized = false;
  }
}
