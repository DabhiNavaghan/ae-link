import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/deep_link_data.dart';
import '../models/link_params.dart';
import '../utils/device_info.dart';
import '../utils/logger.dart';
import 'link_domain_registry.dart';

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
  LinkDomainRegistry? _domainRegistry;

  /// Get stream of deep links
  Stream<DeepLinkData> get onDeepLink => _deepLinkController.stream;

  /// Set config for API calls (called from SDK init)
  void setConfig(SmartLinkConfig config) {
    _config = config;
  }

  /// Supply the registry that decides ours-vs-external.
  ///
  /// Called from SDK init once the link domains have been restored from cache
  /// and refreshed from the backend, so the first link handled here is already
  /// classified against the current list.
  void setDomainRegistry(LinkDomainRegistry registry) {
    _domainRegistry = registry;
  }

  /// Initialize deep link listener
  Future<void> initialize() async {
    try {
      final initialUri = await _getInitialLink();
      if (initialUri != null) {
        SmartLinkLogger.info('App opened via deep link');
        await _handleDeepLink(initialUri);
      }

      _deepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) async {
          SmartLinkLogger.info('Deep link received');
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
  /// Only fires onDeepLink callback for links whose host is one of this app's
  /// link domains (see [LinkDomainRegistry]). External links are logged but
  /// ignored, unless handleExternalDeepLinks is on.
  Future<void> _handleDeepLink(Uri uri) async {
    try {
      final isSmartLink = _isSmartLinkUrl(uri);

      if (isSmartLink) {
        // ── One of our link hosts → resolve short code via API ──
        final shortCode = _extractShortCode(uri);

        if (shortCode != null && _config != null) {
          // Forward query params to resolve API for backend tracking
          final resolved = await _resolveShortCode(
            shortCode,
            queryParams: uri.queryParameters,
            sourceUrl: uri.toString(),
          );
          if (resolved != null) {
            final merged = _mergeQueryParams(resolved, uri.queryParameters);
            _deepLinkController.add(merged);
            SmartLinkLogger.info('✅ Deep link resolved');
            _logDeepLinkData(merged);
            return;
          }

          // Resolve API failed (network error, auth issue, etc.).
          // If the URL carries a deepLink query param, use it directly so
          // the host app still receives the destination instead of silently
          // dropping the event.
          final fallbackDest = uri.queryParameters['deepLink'] ??
              uri.queryParameters['deep_link'] ??
              uri.queryParameters['deeplink'];
          if (fallbackDest != null && fallbackDest.isNotEmpty) {
            SmartLinkLogger.warning(
              'Resolve API failed — using deepLink param as fallback destination',
            );
            final fallback = DeepLinkData(
              destinationUrl: fallbackDest,
              rawUrl: uri.toString(),
              isDeferred: false,
              clickedAt: DateTime.now(),
            );
            _deepLinkController.add(fallback);
            _logDeepLinkData(fallback);
            return;
          }
        }

        SmartLinkLogger.debug('SmartLink URL but short code not found: $uri');
      } else if (_config?.handleExternalDeepLinks == true) {
        // ── External link + flag enabled → parse and pass through ──
        final deepLinkData = DeepLinkData.fromUrl(uri.toString());
        _deepLinkController.add(deepLinkData);
        SmartLinkLogger.info('External deep link passed through: ${uri.host}');
        _logDeepLinkData(deepLinkData);
      } else {
        // ── External link + flag disabled → ignore ──
        SmartLinkLogger.debug(
          'External link ignored (handleExternalDeepLinks: false): ${uri.host}',
        );
      }
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
          'Error processing deep link', e, stackTrace);
    }
  }

  /// Check if a URI belongs to one of our SmartLink domains.
  ///
  /// The domain list is issued by the backend per app and cached on device —
  /// see [LinkDomainRegistry]. Until it is available the SDK trusts only the
  /// configured `apiBaseUrl` host, which is the safe floor.
  bool _isSmartLinkUrl(Uri uri) {
    final registry = _domainRegistry;
    if (registry == null || _config == null) return false;
    return registry.isSmartLinkUrl(uri);
  }

  /// Extract short code from a SmartLink URL
  /// e.g., https://smartlink.apps.allevents.app/xGJEQJR → xGJEQJR
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

  /// Call backend API to resolve short code into full link data.
  /// Forwards all query params from the original URL so the backend
  /// can track them (deepLink, ref, utm_*, etc.) in click metadata.
  /// [sourceUrl] is the URL the link actually arrived on, kept as `rawUrl` so
  /// the host app can tell which link domain opened it.
  Future<DeepLinkData?> _resolveShortCode(
    String shortCode, {
    Map<String, String>? queryParams,
    String? sourceUrl,
  }) async {
    try {
      final params = <String, String>{'shortCode': shortCode};
      if (queryParams != null) params.addAll(queryParams);
      // Forward the real device platform. The SDK's HTTP User-Agent ("Dart/x")
      // does not reveal iOS vs Android, so the backend can only label the click's
      // OS accurately if we send it explicitly here.
      final osName = DeviceInfoHelper.getOsName();
      if (osName == 'ios' || osName == 'android') {
        params['platform'] = osName;
      }
      final url = Uri.parse('${_config!.apiBaseUrl}/api/v1/links/resolve')
          .replace(queryParameters: params);

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
            campaignId: data['campaignId']?.toString(),
            campaignName: data['campaignName']?.toString(),
            campaign: data['campaign'] != null
                ? Map<String, dynamic>.from(data['campaign'])
                : null,
            linkType: data['linkType']?.toString(),
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
            rawUrl: sourceUrl ?? '${_config!.apiBaseUrl}/$shortCode',
          );
        }
      } else {
        SmartLinkLogger.verbose('Short code resolve failed: ${response.statusCode}');
      }
    } catch (e) {
      SmartLinkLogger.verbose('Short code resolve failed: $e');
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

  /// Merge URL query params with resolved link data.
  /// URL params override stored values (e.g., ?utm_source=newvalue).
  /// Maps both snake_case and camelCase query param names.
  DeepLinkData _mergeQueryParams(DeepLinkData data, Map<String, String> query) {
    if (query.isEmpty) return data;

    // Helper to get value: URL param overrides, falls back to stored
    String? pick(String? stored, List<String> keys) {
      for (final k in keys) {
        if (query.containsKey(k) && query[k]!.isNotEmpty) return query[k];
      }
      return stored;
    }

    // Collect custom params from URL (anything not a known key)
    const knownUrlKeys = {
      'utm_source', 'utmSource', 'utm_medium', 'utmMedium',
      'utm_campaign', 'utmCampaign', 'utm_term', 'utmTerm',
      'utm_content', 'utmContent', 'event_id', 'eventId',
      'action', 'user_email', 'userEmail', 'user_id', 'userId',
      'coupon_code', 'couponCode', 'referral_code', 'referralCode',
      'deepLink', 'deep_link', 'deeplink',
    };
    final urlCustom = <String, dynamic>{};
    for (final e in query.entries) {
      if (!knownUrlKeys.contains(e.key)) {
        urlCustom[e.key] = e.value;
      }
    }

    // Merge custom params: stored + URL (URL overrides)
    final mergedCustom = <String, dynamic>{
      ...?data.linkParams?.customParams,
      ...urlCustom,
    };


    final deepLinkUrl = query['deepLink'] ?? query['deep_link'] ?? query['deeplink'];
    final effectiveDestination = deepLinkUrl ?? data.destinationUrl;

    return DeepLinkData(
      linkId: data.linkId,
      deferredLinkId: data.deferredLinkId,
      eventId: pick(data.eventId, ['event_id', 'eventId']),
      action: pick(data.action, ['action']),
      destinationUrl: effectiveDestination,
      campaignId: data.campaignId,
      campaignName: data.campaignName,
      campaign: data.campaign,
      linkType: data.linkType,
      linkParams: LinkParams(
        utmSource: pick(data.linkParams?.utmSource, ['utm_source', 'utmSource']),
        utmMedium: pick(data.linkParams?.utmMedium, ['utm_medium', 'utmMedium']),
        utmCampaign: pick(data.linkParams?.utmCampaign, ['utm_campaign', 'utmCampaign']),
        utmTerm: pick(data.linkParams?.utmTerm, ['utm_term', 'utmTerm']),
        utmContent: pick(data.linkParams?.utmContent, ['utm_content', 'utmContent']),
        userEmail: pick(data.linkParams?.userEmail, ['user_email', 'userEmail']),
        userId: pick(data.linkParams?.userId, ['user_id', 'userId']),
        couponCode: pick(data.linkParams?.couponCode, ['coupon_code', 'couponCode']),
        referralCode: pick(data.linkParams?.referralCode, ['referral_code', 'referralCode']),
        customParams: mergedCustom.isEmpty ? null : mergedCustom,
      ),
      isDeferred: data.isDeferred,
      clickedAt: data.clickedAt,
      rawUrl: data.rawUrl,
    );
  }

  /// Manually process a deep link URL.
  /// Only URLs on one of this app's link domains (see [LinkDomainRegistry])
  /// will fire callbacks.
  void processDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      _handleDeepLink(uri);
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace(
          'Error processing deep link manually', e, stackTrace);
    }
  }

  /// Log deep link data at verbose level (-1)
  void _logDeepLinkData(DeepLinkData data) {
    SmartLinkLogger.data('link', {
      'type': data.isDeferred ? 'deferred' : 'direct',
      'linkId': data.linkId,
      'eventId': data.eventId,
      'action': data.action,
      'destinationUrl': data.destinationUrl,
      'linkType': data.linkType,
    });
    if (data.campaignId != null || data.campaignName != null) {
      SmartLinkLogger.data('campaign', {
        'campaignId': data.campaignId,
        'campaignName': data.campaignName,
        if (data.campaign != null) 'slug': data.campaign?['slug'],
        if (data.campaign != null) 'status': data.campaign?['status'],
      });
    }
    final lp = data.linkParams;
    if (lp != null) {
      SmartLinkLogger.data('params', {
        'utmSource': lp.utmSource,
        'utmMedium': lp.utmMedium,
        'utmCampaign': lp.utmCampaign,
        'couponCode': lp.couponCode,
        'referralCode': lp.referralCode,
        'userEmail': lp.userEmail,
      });
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _deepLinkSubscription.cancel();
    await _deepLinkController.close();
  }
}
