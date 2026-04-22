/// Link parameters and UTM data
class LinkParams {
  /// UTM source
  final String? utmSource;

  /// UTM medium
  final String? utmMedium;

  /// UTM campaign
  final String? utmCampaign;

  /// UTM term
  final String? utmTerm;

  /// UTM content
  final String? utmContent;

  /// User email hint
  final String? userEmail;

  /// User ID hint
  final String? userId;

  /// Coupon code to apply
  final String? couponCode;

  /// Referral code
  final String? referralCode;

  /// Any additional custom parameters
  final Map<String, dynamic>? customParams;

  LinkParams({
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.utmTerm,
    this.utmContent,
    this.userEmail,
    this.userId,
    this.couponCode,
    this.referralCode,
    this.customParams,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'utm_source': utmSource,
      'utm_medium': utmMedium,
      'utm_campaign': utmCampaign,
      'utm_term': utmTerm,
      'utm_content': utmContent,
      'user_email': userEmail,
      'user_id': userId,
      'coupon_code': couponCode,
      'referral_code': referralCode,
      if (customParams != null) ...customParams!,
    };
  }

  /// Create from JSON
  factory LinkParams.fromJson(Map<String, dynamic> json) {
    return LinkParams(
      utmSource: json['utm_source'] as String?,
      utmMedium: json['utm_medium'] as String?,
      utmCampaign: json['utm_campaign'] as String?,
      utmTerm: json['utm_term'] as String?,
      utmContent: json['utm_content'] as String?,
      userEmail: json['user_email'] as String?,
      userId: json['user_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      referralCode: json['referral_code'] as String?,
    );
  }

  /// Get all UTM parameters as a map
  Map<String, String> getUtmParams() {
    final params = <String, String>{};
    if (utmSource != null) params['utm_source'] = utmSource!;
    if (utmMedium != null) params['utm_medium'] = utmMedium!;
    if (utmCampaign != null) params['utm_campaign'] = utmCampaign!;
    if (utmTerm != null) params['utm_term'] = utmTerm!;
    if (utmContent != null) params['utm_content'] = utmContent!;
    return params;
  }

  @override
  String toString() =>
      'LinkParams(utmSource: $utmSource, utmMedium: $utmMedium, utmCampaign: $utmCampaign)';
}
