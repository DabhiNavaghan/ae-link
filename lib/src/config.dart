/// Default SmartLink API base URL (no trailing slash)
const String kSmartLinkDefaultBaseUrl = 'https://smartlink-coral.vercel.app';

/// Configuration for the SmartLink SDK
class SmartLinkConfig {
  /// The base URL of the SmartLink API (trailing slashes are stripped automatically)
  /// Defaults to 'https://smartlink-coral.vercel.app'
  final String apiBaseUrl;

  /// The API key for authentication with the SmartLink backend
  final String tenantApiKey;

  /// Enable debug logging (kept for backward compatibility, use logLevel instead)
  final bool debug;

  /// Log level: -1 = detailed debug, 0 = minimal debug, 1 = release/silent
  final int logLevel;

  /// Timeout duration for API calls in seconds
  final int requestTimeoutSeconds;

  /// Whether to automatically handle incoming deep links
  final bool autoHandleDeepLinks;

  /// Set to true if you're adding SmartLink SDK to an existing app
  /// that already has users. This tells the SDK to skip deferred link
  /// checking for existing users and correctly reports them as
  /// 'return_user' instead of 'first_install'.
  ///
  /// Tip: set this based on whether the user is already logged in
  /// or has existing app data.
  final bool isExistingUser;

  /// Custom headers to include in all API requests
  final Map<String, String>? customHeaders;

  /// Create a new SmartLinkConfig instance
  ///
  /// [logLevel] controls log verbosity:
  ///   -1 = detailed debug (structured output, HTTP bodies, timings)
  ///    0 = minimal debug (key lifecycle events only)
  ///    1 = release / silent (no logs, default)
  ///
  /// [debug] is kept for backward compatibility — if set to true and
  /// logLevel is not explicitly provided, logLevel defaults to 0.
  SmartLinkConfig({
    String apiBaseUrl = kSmartLinkDefaultBaseUrl,
    required this.tenantApiKey,
    this.debug = false,
    int? logLevel,
    this.requestTimeoutSeconds = 30,
    this.autoHandleDeepLinks = true,
    this.isExistingUser = false,
    this.customHeaders,
  }) : apiBaseUrl = apiBaseUrl.endsWith('/')
           ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
           : apiBaseUrl,
       logLevel = logLevel ?? (debug ? 0 : 1);

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
      'SmartLinkConfig(apiBaseUrl: $apiBaseUrl, logLevel: $logLevel, autoHandleDeepLinks: $autoHandleDeepLinks)';
}
