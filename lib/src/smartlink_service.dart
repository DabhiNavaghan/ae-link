import 'dart:async';
import 'package:flutter/material.dart';
import 'smartlink_sdk.dart';
import 'config.dart';
import 'models/deep_link_data.dart';
import 'models/device_info_result.dart';

/// Callback type for handling deep links (app already installed, user clicks link)
typedef DeepLinkCallback = void Function(DeepLinkData data);

/// Callback type for handling deferred deep links (first launch after install via link)
typedef DeferredDeepLinkCallback = void Function(DeepLinkData data);

/// Callback type for handling errors
typedef ErrorCallback = void Function(String message, dynamic error);

/// SmartLink — single entry point for all SmartLink functionality.
///
/// Handles SDK initialization, deferred deep link checking, deep link
/// listening, and cleanup. Use this instead of calling SmartLinkSdk directly.
///
/// **Two separate callbacks:**
/// - [onDeepLink] — fires when the app is already installed and user clicks a link
/// - [onDeferredDeepLink] — fires on first launch if the user installed via a link
///
/// Usage in main.dart:
/// ```dart
/// final smartLink = SmartLink(
///   apiKey: 'your-api-key',
///   onDeepLink: (data) {
///     // App was already installed — user clicked a link
///     // Navigate based on data.eventId, data.action, etc.
///   },
///   onDeferredDeepLink: (data) {
///     // First launch after install via a link
///     // Navigate to the content they originally clicked
///   },
/// );
/// await smartLink.initialize();
/// ```
class SmartLink {
  /// Backend API base URL (defaults to https://smartlink-coral.vercel.app)
  final String apiBaseUrl;

  /// Tenant API key from the SmartLink dashboard
  final String apiKey;

  /// Called when a direct deep link is received (app already installed,
  /// user clicks a SmartLink URL and it opens the app directly).
  final DeepLinkCallback? onDeepLink;

  /// Called when a deferred deep link is matched (first launch after
  /// the user installed the app by clicking a SmartLink URL).
  final DeferredDeepLinkCallback? onDeferredDeepLink;

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
  /// SmartLink(
  ///   apiKey: 'KEY',
  ///   isExistingUser: authService.isLoggedIn,
  ///   onDeepLink: (data) { ... },
  ///   onDeferredDeepLink: (data) { ... },
  /// )
  /// ```
  final bool isExistingUser;

  StreamSubscription<DeepLinkData>? _deepLinkSubscription;
  bool _initialized = false;

  SmartLink({
    this.apiBaseUrl = kSmartLinkDefaultBaseUrl,
    required this.apiKey,
    this.onDeepLink,
    this.onDeferredDeepLink,
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
  /// 3. Starts listening for incoming direct deep links
  ///
  /// Returns the deferred [DeepLinkData] if found on first launch, null otherwise.
  Future<DeepLinkData?> initialize() async {
    if (_initialized) return null;

    try {
      // 1. Initialize SDK
      await SmartLinkSdk.initialize(
        SmartLinkConfig(
          apiBaseUrl: apiBaseUrl,
          tenantApiKey: apiKey,
          debug: debug,
          requestTimeoutSeconds: timeoutSeconds,
          autoHandleDeepLinks: autoHandleDeepLinks,
          isExistingUser: isExistingUser,
        ),
      );

      // 2. Listen for DIRECT deep links only (app already installed)
      _deepLinkSubscription = SmartLinkSdk.onDeepLink.listen(
        (data) {
          // Only fire onDeepLink for direct links, not deferred
          if (!data.isDeferred) {
            onDeepLink?.call(data);
          }
        },
        onError: (error) {
          onError?.call('Deep link stream error', error);
        },
      );

      // 3. Check for deferred deep link on first launch
      final deferredLink = await SmartLinkSdk.checkDeferredLink();

      _initialized = true;

      // 4. Fire deferred callback separately if matched
      if (deferredLink != null) {
        // Auto-confirm deferred link
        if (deferredLink.deferredLinkId != null) {
          SmartLinkSdk.confirmDeepLink(deferredLink.deferredLinkId!);
        }

        // Fire the deferred callback
        onDeferredDeepLink?.call(deferredLink);
      }

      return deferredLink;
    } catch (e) {
      onError?.call('SmartLink initialization failed', e);
      return null;
    }
  }

  /// Manually process a deep link URL (e.g., from a push notification)
  void handleUrl(String url) {
    SmartLinkSdk.processDeepLink(url);
  }

  /// Force check for deferred deep link (ignores first-launch check)
  Future<DeepLinkData?> forceCheckDeferred() async {
    try {
      return await SmartLinkSdk.forceCheckDeferredLink();
    } catch (e) {
      onError?.call('Force deferred check failed', e);
      return null;
    }
  }

  /// Get the device ID assigned by the SDK
  String? get deviceId => SmartLinkSdk.getDeviceId();

  /// Collect comprehensive device, app, and environment information.
  ///
  /// Returns a [DeviceInfoResult] with platform, OS, screen, locale,
  /// network, battery, hardware capabilities, and accessibility data.
  Future<DeviceInfoResult> getDeviceInfo() => SmartLinkSdk.getDeviceInfo();

  /// Whether the SDK has been initialized
  bool get isInitialized => _initialized;

  /// Get the last received deep link (either direct or deferred)
  DeepLinkData? get lastDeepLink => SmartLinkSdk.lastDeepLink;

  /// Cleanup — call in your app's dispose
  Future<void> dispose() async {
    await _deepLinkSubscription?.cancel();
    await SmartLinkSdk.dispose();
    _initialized = false;
  }
}
