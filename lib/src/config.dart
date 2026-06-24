/// Default SmartLink API base URL (no trailing slash)
const String kSmartLinkDefaultBaseUrl = 'https://smartlink.apps.allevents.app';

/// Configuration for the SmartLink SDK
class SmartLinkConfig {
  /// The base URL of the SmartLink API (trailing slashes are stripped automatically)
  /// Defaults to 'https://smartlink-coral.vercel.app'
  final String apiBaseUrl;

  /// The API key for authentication with the SmartLink backend
  final String tenantApiKey;

  /// Log level: -1 = detailed debug, 0 = minimal debug, 1 = release/silent
  final int logLevel;

  /// Timeout duration for API calls in seconds
  final int requestTimeoutSeconds;

  /// Whether to handle external deep links (links not from the SmartLink domain).
  ///
  /// - `false` (default): Only links from your SmartLink domain
  ///   (apiBaseUrl) trigger onDeepLink / onDeferredDeepLink callbacks.
  ///   External links are silently ignored by the SDK.
  /// - `true`: All deep links are processed, including external ones.
  ///   External links are parsed from the URL and delivered via onDeepLink.
  final bool handleExternalDeepLinks;

  /// Custom headers to include in all API requests
  final Map<String, String>? customHeaders;

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
    this.customHeaders,
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
