import 'dart:async';
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
/// Only [apiKey] is required. [apiBaseUrl] defaults to the production backend
/// and [linkDomains] is issued by that backend at init, scoped to the key —
/// neither belongs in app code unless you are self-hosting.
///
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
  /// Backend API base URL (defaults to https://smartlink.apps.allevents.app)
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

  /// Log level: -1 = detailed debug, 0 = minimal debug, 1 = release/silent
  final int? logLevel;

  /// API request timeout in seconds
  final int timeoutSeconds;

  /// Whether to handle external deep links (links not from a SmartLink domain).
  ///
  /// - `false` (default): Only dashboard-created links trigger callbacks.
  /// - `true`: All deep links (including external) are passed to onDeepLink.
  ///
  /// Links on your app's own link domains are never treated as external —
  /// they are always resolved through the backend, whatever this flag says.
  final bool handleExternalDeepLinks;

  /// Optional override: extra hosts to treat as first-party link domains.
  ///
  /// **Normally unnecessary.** Your app's link domains are managed in the
  /// dashboard and fetched at init, so nothing tenant-specific is compiled
  /// into the app. Set this only for a self-hosted deployment that cannot
  /// rely on the server list. See [SmartLinkConfig.linkDomains].
  final List<String> linkDomains;

  /// Whether event tracking is available at all.
  ///
  /// Set to `false` to disable [track], [identify] and all automatic events —
  /// useful for honouring a user's analytics opt-out. Deep linking and
  /// attribution keep working either way.
  final bool enableEventTracking;

  /// Whether the SDK emits lifecycle events on its own.
  ///
  /// When `true` (default) it tracks `app_install`, `app_open`,
  /// `session_start` and `deep_link_opened` without you writing any tracking
  /// code — enough to populate a funnel on day one.
  final bool enableAutomaticEvents;

  StreamSubscription<DeepLinkData>? _deepLinkSubscription;
  bool _initialized = false;

  SmartLink({
    this.apiBaseUrl = kSmartLinkDefaultBaseUrl,
    required this.apiKey,
    this.onDeepLink,
    this.onDeferredDeepLink,
    this.onError,
    this.logLevel,
    this.timeoutSeconds = 30,
    this.handleExternalDeepLinks = false,
    this.linkDomains = const [],
    this.enableEventTracking = true,
    this.enableAutomaticEvents = true,
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
      // 1. Subscribe to the SDK stream BEFORE initializing.
      //    SmartLinkSdk uses a broadcast stream — if we subscribe after
      //    initialize(), the cold-start deep link is emitted and lost
      //    before we're listening.
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

      // 2. Initialize SDK (may emit the initial deep link during init)
      await SmartLinkSdk.initialize(
        SmartLinkConfig(
          apiBaseUrl: apiBaseUrl,
          tenantApiKey: apiKey,
          logLevel: logLevel,
          requestTimeoutSeconds: timeoutSeconds,
          handleExternalDeepLinks: handleExternalDeepLinks,
          linkDomains: linkDomains,
          enableEventTracking: enableEventTracking,
          enableAutomaticEvents: enableAutomaticEvents,
        ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // Event tracking
  //
  // Thin delegations to SmartLinkSdk, so tracking is reachable from the same
  // object you already hold. Everything difficult — the on-disk queue, batching,
  // retry, sessions, offline identify replay — lives in TrackingService.
  // ══════════════════════════════════════════════════════════════════════════

  /// Track an event.
  ///
  /// ```dart
  /// await smartLink.track(
  ///   'ticket_purchase',
  ///   value: 1250,
  ///   currency: 'INR',
  ///   properties: {'event_id': 'evt_991', 'qty': 2},
  /// );
  /// ```
  ///
  /// Returns as soon as the event is queued on disk — it survives a cold start
  /// and flushes when connectivity returns. Never throws for network reasons:
  /// a checkout must not fail because analytics did.
  ///
  /// [name] must match `^[a-z][a-z0-9_]{0,63}$`. Names are a small fixed
  /// vocabulary — put ids, titles and other varying values in [properties].
  ///
  /// Do not put personal data in [properties]; the server drops keys that look
  /// like emails, phone numbers or names. Use [identify] for that.
  Future<void> track(
    String name, {
    num? value,
    String? currency,
    Map<String, dynamic>? properties,
  }) =>
      SmartLinkSdk.track(
        name,
        value: value,
        currency: currency,
        properties: properties,
      );

  /// Attach this device to a signed-in user.
  ///
  /// Everything tracked after this carries the user. Events tracked *before* it
  /// on this device are backfilled server-side, bounded so they can never reach
  /// across a previous sign-out — whoever used this device before keeps their
  /// own history.
  ///
  /// The first call also fixes the user's acquisition source: the link and
  /// campaign that brought them in, permanently, across every device they later
  /// sign in on.
  Future<bool> identify(
    String userId, {
    Map<String, dynamic>? traits,
    String? email,
  }) =>
      SmartLinkSdk.identify(userId, traits: traits, email: email);

  /// End the signed-in session on this device.
  ///
  /// Keeps the device id deliberately — rotating it would sever install
  /// attribution and make the next launch look like a fresh install.
  Future<bool> logout() => SmartLinkSdk.logout();

  /// Send everything queued right now.
  ///
  /// Worth calling before a known exit — a checkout completing, the app being
  /// backgrounded — so those events don't wait for the next interval.
  Future<void> flush() => SmartLinkSdk.flush();

  /// The user id this device is currently identified as, if any.
  String? get currentUserId => SmartLinkSdk.currentUserId;

  /// Events still waiting to be sent.
  int get queuedEventCount => SmartLinkSdk.queuedEventCount;

  /// Events discarded because the queue overflowed or exhausted its retries.
  /// Non-zero means data was lost — worth surfacing rather than hiding.
  int get droppedEventCount => SmartLinkSdk.droppedEventCount;

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
