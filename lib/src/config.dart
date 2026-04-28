/// Default SmartLink API base URL (no trailing slash)
const String kSmartLinkDefaultBaseUrl = 'https://smartlink-coral.vercel.app';

/// Configuration for the SmartLink SDK
class SmartLinkConfig {
  /// The base URL of the SmartLink API (trailing slashes are stripped automatically)
  /// Defaults to 'https://smartlink-coral.vercel.app'
  final String apiBaseUrl;

  /// The API key for authentication with the SmartLink backend
  final String tenantApiKey;

  /// Enable debug logging
  final bool debug;

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
  /// Only [tenantApiKey] is required. The [apiBaseUrl] defaults to
  /// 'https://smartlink-coral.vercel.app'.
  ///
  /// Trailing slashes in [apiBaseUrl] are stripped automatically to
  /// prevent double-slash URLs (e.g. `https://host//api/v1/...`)
  /// which cause 308 redirects on Vercel/Next.js.
  SmartLinkConfig({
    String apiBaseUrl = kSmartLinkDefaultBaseUrl,
    required this.tenantApiKey,
    this.debug = false,
    this.requestTimeoutSeconds = 30,
    this.autoHandleDeepLinks = true,
    this.isExistingUser = false,
    this.customHeaders,
  }) : apiBaseUrl = apiBaseUrl.endsWith('/')
           ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
           : apiBaseUrl;

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
      'SmartLinkConfig(apiBaseUrl: $apiBaseUrl, debug: $debug, autoHandleDeepLinks: $autoHandleDeepLinks)';
}
