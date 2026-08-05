import 'dart:convert';

/// One tracked event, as it sits in the offline queue and goes over the wire.
///
/// Everything needed to send this event is captured at `track()` time, not at
/// flush time. An event that happened while offline must carry the timestamp,
/// session and device it actually had — not the ones that happen to be current
/// when connectivity returns three days later.
class TrackedEvent {
  /// Event name. Server-side contract is `^[a-z][a-z0-9_]{0,63}$`.
  final String name;

  final String? deviceId;
  final String? sessionId;

  /// Client clock at the moment track() was called.
  final DateTime occurredAt;

  final num? value;
  final String? currency;

  final Map<String, dynamic>? properties;

  /// Minted at enqueue, never at send, so a retry is provably the same event
  /// and the server's unique index can collapse it to a no-op.
  final String idempotencyKey;

  final String? platform;
  final String? sdkVersion;
  final String? appVersion;

  /// Set when this event followed a deep link the SDK opened, so the server can
  /// skip the attribution ladder and use the exact click.
  final String? clickId;

  /// How many send attempts this event has survived. Used for backoff and for
  /// the poison-pill cutoff.
  final int attempts;

  const TrackedEvent({
    required this.name,
    required this.occurredAt,
    required this.idempotencyKey,
    this.deviceId,
    this.sessionId,
    this.value,
    this.currency,
    this.properties,
    this.platform,
    this.sdkVersion,
    this.appVersion,
    this.clickId,
    this.attempts = 0,
  });

  TrackedEvent copyWith({int? attempts, String? deviceId, String? sessionId}) {
    return TrackedEvent(
      name: name,
      occurredAt: occurredAt,
      idempotencyKey: idempotencyKey,
      deviceId: deviceId ?? this.deviceId,
      sessionId: sessionId ?? this.sessionId,
      value: value,
      currency: currency,
      properties: properties,
      platform: platform,
      sdkVersion: sdkVersion,
      appVersion: appVersion,
      clickId: clickId,
      attempts: attempts ?? this.attempts,
    );
  }

  /// The wire format the ingest API expects.
  Map<String, dynamic> toApiJson() {
    return {
      'name': name,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'idempotencyKey': idempotencyKey,
      if (deviceId != null) 'deviceId': deviceId,
      if (sessionId != null) 'sessionId': sessionId,
      if (value != null) 'value': value,
      if (currency != null) 'currency': currency,
      if (properties != null && properties!.isNotEmpty) 'properties': properties,
      if (platform != null) 'platform': platform,
      if (sdkVersion != null) 'sdkVersion': sdkVersion,
      if (appVersion != null) 'appVersion': appVersion,
      if (clickId != null) 'clickId': clickId,
    };
  }

  /// Storage format — the wire format plus the local retry counter.
  Map<String, dynamic> toStorageJson() => {
        ...toApiJson(),
        '_attempts': attempts,
      };

  static TrackedEvent? fromStorageJson(Map<String, dynamic> json) {
    final name = json['name'];
    final occurredAt = json['occurredAt'];
    final key = json['idempotencyKey'];

    // A row missing any of these can never be sent successfully. Returning null
    // lets the queue drop it instead of retrying it forever.
    if (name is! String || occurredAt is! String || key is! String) return null;

    final parsed = DateTime.tryParse(occurredAt);
    if (parsed == null) return null;

    return TrackedEvent(
      name: name,
      occurredAt: parsed,
      idempotencyKey: key,
      deviceId: json['deviceId'] as String?,
      sessionId: json['sessionId'] as String?,
      value: json['value'] as num?,
      currency: json['currency'] as String?,
      properties: (json['properties'] as Map?)?.cast<String, dynamic>(),
      platform: json['platform'] as String?,
      sdkVersion: json['sdkVersion'] as String?,
      appVersion: json['appVersion'] as String?,
      clickId: json['clickId'] as String?,
      attempts: (json['_attempts'] as int?) ?? 0,
    );
  }

  String encode() => jsonEncode(toStorageJson());

  static TrackedEvent? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromStorageJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'TrackedEvent($name, occurredAt: $occurredAt, attempts: $attempts)';
}
