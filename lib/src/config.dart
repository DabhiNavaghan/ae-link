/// Default SmartLink API base URL (no trailing slash)
const String kSmartLinkDefaultBaseUrl = 'https://smartlink.apps.allevents.app';

/// Configuration for the SmartLink SDK
class SmartLinkConfig {
  /// The base URL of the SmartLink API (trailing slashes are stripped automatically)
  /// Defaults to 'https://smartlink.apps.allevents.app'
  final String apiBaseUrl;

  /// The API key for authentication with the SmartLink backend
  final String tenantApiKey;

  /// Log level: -1 = detailed debug, 0 = minimal debug, 1 = release/silent
  final int logLevel;

  /// Timeout duration for API calls in seconds
  final int requestTimeoutSeconds;

  /// Whether to handle external deep links (links not from a SmartLink domain).
  ///
  /// - `false` (default): Only links whose host is one of your app's link
  ///   domains — see [LinkDomainRegistry] — trigger onDeepLink /
  ///   onDeferredDeepLink. External links are silently ignored by the SDK.
  /// - `true`: All deep links are processed, including external ones.
  ///   External links are parsed from the URL and delivered via onDeepLink.
  ///
  /// This flag has no bearing on your own link domains — those are always
  /// resolved through the backend.
  final bool handleExternalDeepLinks;

  /// Optional override: extra hosts to treat as first-party SmartLink domains.
  ///
  /// **You normally do not need this.** The SDK fetches your app's link
  /// domains from the backend at init (scoped to your API key) and caches them
  /// on device, so nothing tenant-specific is compiled into the app binary.
  /// Manage the list in the dashboard instead.
  ///
  /// Use this only when the server list cannot be relied on — a self-hosted
  /// deployment, or an air-gapped build that must classify links before its
  /// first successful init:
  ///
  /// ```dart
  /// SmartLinkConfig(
  ///   tenantApiKey: '...',
  ///   linkDomains: ['links.mybrand.com', '*.mybrand.io'],
  /// )
  /// ```
  ///
  /// A `*.` prefix matches that domain and all of its subdomains; a bare host
  /// matches exactly. Full URLs are accepted and reduced to their host.
  /// Entries too broad to be safe (a bare TLD, `*.com`) are discarded.
  final List<String> linkDomains;

  /// Custom headers to include in all API requests
  final Map<String, String>? customHeaders;

  /// Whether the SDK emits lifecycle events on its own.
  ///
  /// When `true` (default), the SDK tracks `app_install`, `app_open`,
  /// `session_start` and `deep_link_opened` without the host app writing any
  /// tracking code — enough to populate a funnel on day one. Set to `false` if
  /// you would rather send everything explicitly.
  final bool enableAutomaticEvents;

  /// Whether event tracking is enabled at all.
  ///
  /// Set to `false` to disable `track()`, `identify()` and all automatic
  /// events — useful for honouring a user's analytics opt-out. Deep linking and
  /// attribution continue to work.
  final bool enableEventTracking;

  /// Create a new SmartLinkConfig instance
  ///
  /// [logLevel] controls log verbosity:
  ///   -1 = detailed debug (structured output, HTTP bodies, timings)
  ///    0 = minimal debug (key lifecycle events only)
  ///    1 = release / silent (no logs, default)
  SmartLinkConfig({
    String apiBaseUrl = kSmartLinkDefaultBaseUrl,
    required this.tenantApiKey,
    int? logLevel,
    this.requestTimeoutSeconds = 30,
    this.handleExternalDeepLinks = false,
    this.linkDomains = const [],
    this.customHeaders,
    this.enableAutomaticEvents = true,
    this.enableEventTracking = true,
  }) : apiBaseUrl = apiBaseUrl.endsWith('/')
           ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
           : apiBaseUrl,
       logLevel = logLevel ?? 1;

  /// Get the complete headers for API requests
  Map<String, String> getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-API-Key': tenantApiKey,
      ...?customHeaders,
    };
    return headers;
  }

  /// Validate the configuration
  bool validate() {
    return apiBaseUrl.isNotEmpty && tenantApiKey.isNotEmpty;
  }

  @override
  String toString() =>
      'SmartLinkConfig(apiBaseUrl: $apiBaseUrl, logLevel: $logLevel)';
}
