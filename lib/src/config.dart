/// Configuration for the AE-LINK SDK
class AeLinkConfig {
  /// The base URL of the AE-LINK API (e.g., 'https://allevents.in')
  final String apiBaseUrl;

  /// The API key for authentication with the AE-LINK backend
  final String tenantApiKey;

  /// Enable debug logging
  final bool debug;

  /// Timeout duration for API calls in seconds
  final int requestTimeoutSeconds;

  /// Whether to automatically handle incoming deep links
  final bool autoHandleDeepLinks;

  /// Custom headers to include in all API requests
  final Map<String, String>? customHeaders;

  /// Create a new AeLinkConfig instance
  AeLinkConfig({
    required this.apiBaseUrl,
    required this.tenantApiKey,
    this.debug = false,
    this.requestTimeoutSeconds = 30,
    this.autoHandleDeepLinks = true,
    this.customHeaders,
  });

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
      'AeLinkConfig(apiBaseUrl: $apiBaseUrl, debug: $debug, autoHandleDeepLinks: $autoHandleDeepLinks)';
}
