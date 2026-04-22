import 'link_params.dart';

/// Deep link data resolved from deferred or direct deep link
class DeepLinkData {
  /// Unique identifier for this link
  final String? linkId;

  /// Deferred link ID (null if not from deferred matching)
  final String? deferredLinkId;

  /// Event ID to navigate to
  final String? eventId;

  /// Action to perform (view_event, view_ticket, buy_ticket, etc.)
  final String? action;

  /// Destination URL if applicable
  final String? destinationUrl;

  /// UTM parameters and other link data
  final LinkParams? linkParams;

  /// Whether this link came from deferred matching
  final bool isDeferred;

  /// When the link was clicked/matched
  final DateTime? clickedAt;

  /// Raw deep link URL
  final String? rawUrl;

  DeepLinkData({
    this.linkId,
    this.deferredLinkId,
    this.eventId,
    this.action,
    this.destinationUrl,
    this.linkParams,
    this.isDeferred = false,
    this.clickedAt,
    this.rawUrl,
  });

  /// Get UTM parameters as a map
  Map<String, String> get utmParams => linkParams?.getUtmParams() ?? {};

  /// Get user email if available
  String? get userEmail => linkParams?.userEmail;

  /// Get user ID if available
  String? get userId => linkParams?.userId;

  /// Get coupon code if available
  String? get couponCode => linkParams?.couponCode;

  /// Get referral code if available
  String? get referralCode => linkParams?.referralCode;

  /// Get custom parameters
  Map<String, dynamic>? get customParams => linkParams?.customParams;

  /// Convert to JSON for storage/API
  Map<String, dynamic> toJson() {
    return {
      'link_id': linkId,
      'deferred_link_id': deferredLinkId,
      'event_id': eventId,
      'action': action,
      'destination_url': destinationUrl,
      'is_deferred': isDeferred,
      'clicked_at': clickedAt?.toIso8601String(),
      'raw_url': rawUrl,
      if (linkParams != null) 'link_params': linkParams!.toJson(),
    };
  }

  /// Create from JSON
  factory DeepLinkData.fromJson(Map<String, dynamic> json) {
    return DeepLinkData(
      linkId: json['link_id'] as String?,
      deferredLinkId: json['deferred_link_id'] as String?,
      eventId: json['event_id'] as String?,
      action: json['action'] as String?,
      destinationUrl: json['destination_url'] as String?,
      linkParams: json['link_params'] != null
          ? LinkParams.fromJson(json['link_params'] as Map<String, dynamic>)
          : null,
      isDeferred: json['is_deferred'] as bool? ?? false,
      clickedAt: json['clicked_at'] != null
          ? DateTime.parse(json['clicked_at'] as String)
          : null,
      rawUrl: json['raw_url'] as String?,
    );
  }

  /// Create from deep link URL
  factory DeepLinkData.fromUrl(String url) {
    final uri = Uri.parse(url);

    return DeepLinkData(
      rawUrl: url,
      destinationUrl: url,
      eventId: uri.queryParameters['event_id'],
      action: uri.queryParameters['action'],
      linkParams: LinkParams(
        utmSource: uri.queryParameters['utm_source'],
        utmMedium: uri.queryParameters['utm_medium'],
        utmCampaign: uri.queryParameters['utm_campaign'],
        utmTerm: uri.queryParameters['utm_term'],
        utmContent: uri.queryParameters['utm_content'],
        userEmail: uri.queryParameters['user_email'],
        userId: uri.queryParameters['user_id'],
        couponCode: uri.queryParameters['coupon_code'],
        referralCode: uri.queryParameters['referral_code'],
      ),
      isDeferred: false,
      clickedAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'DeepLinkData(eventId: $eventId, action: $action, isDeferred: $isDeferred, deferredLinkId: $deferredLinkId)';
}
