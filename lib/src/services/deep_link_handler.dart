import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/deep_link_data.dart';
import '../models/link_params.dart';
import '../utils/logger.dart';

/// Service for handling incoming deep links via Universal Links / App Links
///
/// When the app is already installed and the user clicks a SmartLink URL,
/// this handler receives the URL, extracts the short code, calls the
/// backend API to resolve it, and delivers the full link data.
class DeepLinkHandler {
  final AppLinks _appLinks = AppLinks();
  late StreamSubscription<Uri> _deepLinkSubscription;
  final StreamController<DeepLinkData> _deepLinkController =
      StreamController<DeepLinkData>.broadcast();

  SmartLinkConfig? _config;

  /// Get stream of deep links
  Stream<DeepLinkData> get onDeepLink => _deepLinkController.stream;

  /// Set config for API calls (called from SDK init)
  void setConfig(SmartLinkConfig config) {
    _config = config;
  }

  /// Initialize deep link listener
  Future<void> initialize() async {
    try {
      final initialUri = await _getInitialLink();
      if (initialUri != null) {
        SmartLinkLogger.info('App opened via deep link: $initialUri');
        await _handleDeepLink(initialUri);
      }

      _deepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) async {
          SmartLinkLogger.info('Deep link received: $uri');
          await _handleDeepLink(uri);
        },
        onError: (err) {
          SmartLinkLogger.error('Deep link error', err);
        },
      );
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
          'Error initializing deep link handler', e, stackTrace);
      rethrow;
    }
  }

  /// Get initial link — works across all app_links versions
  Future<Uri?> _getInitialLink() async {
    final dynamic links = _appLinks;

    try {
      final result = await links.getInitialLink();
      if (result != null) return result as Uri;
    } catch (_) {}

    try {
      final result = await links.getInitialAppLink();
      if (result != null) return result as Uri;
    } catch (_) {}

    return null;
  }

  /// Handle incoming deep link URI
  ///
  /// If the URL is a SmartLink short code URL (e.g., smartlink.vercel.app/xGJEQJR),
  /// resolve it via the API to get full link data (params, destination, etc.)
  Future<void> _handleDeepLink(Uri uri) async {
    try {
      // Extract short code from URL path
      final shortCode = _extractShortCode(uri);

      if (shortCode != null && _config != null) {
        // Resolve short code via API to get full link data
        final resolved = await _resolveShortCode(shortCode);
        if (resolved != null) {
          _deepLinkController.add(resolved);
          SmartLinkLogger.info('Deep link resolved: ${resolved.eventId ?? resolved.destinationUrl}');
          return;
        }
      }

      // Fallback: parse whatever we can from the URL directly
      final deepLinkData = DeepLinkData.fromUrl(uri.toString());
      _deepLinkController.add(deepLinkData);
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
          'Error processing deep link', e, stackTrace);
    }
  }

  /// Extract short code from a SmartLink URL
  /// e.g., https://smartlink.vercel.app/xGJEQJR → xGJEQJR
  String? _extractShortCode(Uri uri) {
    final path = uri.path;
    // Short codes are single path segment, 5-12 alphanumeric chars
    if (path.isEmpty) return null;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length == 1) {
      final code = segments[0];
      // Validate it looks like a short code (not a known route)
      if (code.length >= 4 &&
          code.length <= 15 &&
          RegExp(r'^[a-zA-Z0-9]+$').hasMatch(code)) {
        return code;
      }
    }
    return null;
  }

  /// Call backend API to resolve short code into full link data
  Future<DeepLinkData?> _resolveShortCode(String shortCode) async {
    try {
      final url = Uri.parse(
          '${_config!.apiBaseUrl}/api/v1/links/resolve?shortCode=$shortCode');

      final response = await http.Client()
          .get(url, headers: _config!.getHeaders())
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'];

        if (data != null) {
          final params = data['params'] as Map<String, dynamic>? ?? {};

          return DeepLinkData(
            linkId: data['linkId']?.toString(),
            eventId: params['eventId']?.toString(),
            action: params['action']?.toString(),
            destinationUrl: data['destinationUrl']?.toString(),
            linkParams: LinkParams(
              utmSource: params['utmSource']?.toString(),
              utmMedium: params['utmMedium']?.toString(),
              utmCampaign: params['utmCampaign']?.toString(),
              utmTerm: params['utmTerm']?.toString(),
              utmContent: params['utmContent']?.toString(),
              userEmail: params['userEmail']?.toString(),
              userId: params['userId']?.toString(),
              couponCode: params['couponCode']?.toString(),
              referralCode: params['referralCode']?.toString(),
              customParams: _extractCustomParams(params),
            ),
            isDeferred: false,
            clickedAt: DateTime.now(),
            rawUrl: '${_config!.apiBaseUrl}/$shortCode',
          );
        }
      } else {
        SmartLinkLogger.debug('Failed to resolve short code: ${response.statusCode}');
      }
    } catch (e) {
      SmartLinkLogger.debug('Short code resolve failed: $e');
    }
    return null;
  }

  /// Extract custom params (anything that's not a known key)
  Map<String, dynamic>? _extractCustomParams(Map<String, dynamic> params) {
    const knownKeys = {
      'eventId', 'action', 'utmSource', 'utmMedium', 'utmCampaign',
      'utmTerm', 'utmContent', 'userEmail', 'userId', 'couponCode',
      'referralCode',
    };

    final custom = <String, dynamic>{};
    for (final entry in params.entries) {
      if (!knownKeys.contains(entry.key) && entry.key != 'custom') {
        custom[entry.key] = entry.value;
      }
    }
    // Also include the 'custom' sub-object if present
    if (params['custom'] is Map) {
      custom.addAll(Map<String, dynamic>.from(params['custom']));
    }

    return custom.isEmpty ? null : custom;
  }

  /// Manually process a deep link URL
  void processDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      _handleDeepLink(uri);
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
          'Error processing deep link manually', e, stackTrace);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _deepLinkSubscription.cancel();
    await _deepLinkController.close();
  }
}
