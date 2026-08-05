import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/tracked_event.dart';
import '../utils/device_info.dart';
import '../utils/logger.dart';
import 'storage_service.dart';

/// SDK version reported on every event, so a bad release is identifiable in the
/// data rather than by guesswork.
///
/// Keep this in step with `version:` in pubspec.yaml. Dart cannot read the
/// pubspec at compile time, so the constant is the single place it lives on the
/// wire — and a stale value here silently mislabels every event.
const String kSmartLinkSdkVersion = '1.1.0';

/// Event tracking: queueing, batching, retry, sessions and identity replay.
///
/// The public surface of all this is one method — `smartLink.track()` (or `SmartLinkSdk.track()`). Everything
/// difficult lives here:
///
///   * The queue is on disk, so events survive a cold start. A crash between
///     `track()` and the next flush loses nothing.
///   * Idempotency keys are minted at enqueue. A retry after an ambiguous
///     network failure is provably the same event, and the server collapses it.
///   * The queue is capped and drops oldest-first with a counter. An app that
///     is offline for a week must not grow an unbounded queue.
///   * `identify()` is persisted and replayed, so signing in offline still
///     works.
class TrackingService {
  final SmartLinkConfig config;
  final StorageService storage;

  TrackingService({required this.config, required this.storage});

  final _uuid = const Uuid();
  final _random = Random();
  http.Client _httpClient = http.Client();

  Timer? _flushTimer;
  bool _flushing = false;
  bool _disposed = false;

  /// Consecutive failed flushes, used for exponential backoff.
  int _consecutiveFailures = 0;
  DateTime? _nextAttemptAfter;

  String? _cachedDeviceId;
  String? _appVersion;

  // ── Tunables ─────────────────────────────────────────────────────────────

  /// Matches the server's per-request ceiling. Sending more would be rejected wholesale.
  static const int batchSize = 50;

  /// Flush interval when the queue hasn't filled a batch on its own.
  static const Duration flushInterval = Duration(seconds: 30);

  /// Hard cap on the on-disk queue. Beyond this, the oldest events are dropped —
  /// bounded loss with a counter beats an unbounded queue that eventually
  /// exhausts storage.
  static const int maxQueueSize = 1000;

  /// A new session starts after this much time backgrounded. Thirty minutes is
  /// the industry convention, so these numbers are comparable with everyone else's.
  static const Duration sessionTimeout = Duration(minutes: 30);

  /// Give up on an individual event after this many failed sends. Without a
  /// cutoff, one permanently-rejected event blocks the queue behind it forever.
  static const int maxAttemptsPerEvent = 10;

  static const Duration _maxBackoff = Duration(minutes: 5);

  // ── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> initialize({String? deviceId, String? appVersion}) async {
    _cachedDeviceId = deviceId;
    _appVersion = appVersion;
    _startFlushTimer();

    // Anything left in the queue from the last run goes out first, and any
    // identify() that never made it is replayed before those events send.
    unawaited(_replayPendingIdentify());
    unawaited(flush());
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) {
      unawaited(flush());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    // Best-effort final drain so events buffered right before teardown aren't
    // stranded until the next launch.
    await flush();
    _httpClient.close();
  }

  // ── Sessions ─────────────────────────────────────────────────────────────

  /// Current session id, rotating after [sessionTimeout] of inactivity.
  Future<String> currentSessionId() async {
    final now = DateTime.now();
    final lastActive = storage.getSessionLastActive();
    var sessionId = storage.getSessionId();

    final expired =
        lastActive == null || now.difference(lastActive) > sessionTimeout;

    if (sessionId == null || expired) {
      sessionId = _uuid.v4();
      await storage.setSessionId(sessionId);
      SmartLinkLogger.debug('New session: $sessionId');
    }

    await storage.setSessionLastActive(now);
    return sessionId;
  }

  /// True when the next [currentSessionId] call would start a fresh session.
  bool get sessionExpired {
    final lastActive = storage.getSessionLastActive();
    return lastActive == null ||
        DateTime.now().difference(lastActive) > sessionTimeout;
  }

  // ── Track ────────────────────────────────────────────────────────────────

  /// Queue an event.
  ///
  /// Returns immediately — the event is written to disk and sent by the
  /// batcher. It never throws for network reasons; a caller's purchase flow
  /// must not fail because analytics did.
  Future<void> track(
    String name, {
    num? value,
    String? currency,
    Map<String, dynamic>? properties,
    String? clickId,
    DateTime? occurredAt,
  }) async {
    if (_disposed) return;

    // Validate locally against the same rule the server enforces, so a mistake
    // shows up in the developer's console rather than as a silent 207 rejection.
    if (!_isValidEventName(name)) {
      SmartLinkLogger.warning(
        'track("$name") ignored — event names must match '
        '^[a-z][a-z0-9_]{0,63}\$ (lowercase letters, digits, underscores)',
      );
      return;
    }

    try {
      final deviceId = _cachedDeviceId ?? storage.getDeviceId();
      final sessionId = await currentSessionId();

      final event = TrackedEvent(
        name: name,
        // The client clock at the moment this happened. The server stores its
        // own receive time alongside it and the gap is a health metric, so an
        // event replayed days later still reports when it actually occurred.
        occurredAt: occurredAt ?? DateTime.now(),
        idempotencyKey: _uuid.v4(),
        deviceId: deviceId,
        sessionId: sessionId,
        value: value,
        currency: currency,
        properties: properties,
        platform: DeviceInfoHelper.getOsName(),
        sdkVersion: kSmartLinkSdkVersion,
        appVersion: _appVersion,
        clickId: clickId,
      );

      await _enqueue(event);

      // Send eagerly once a full batch is available, rather than waiting out
      // the timer.
      final queue = storage.getEventQueue();
      if (queue.length >= batchSize) {
        unawaited(flush());
      }
    } catch (e) {
      SmartLinkLogger.debug('track("$name") failed to enqueue: $e');
    }
  }

  Future<void> _enqueue(TrackedEvent event) async {
    final queue = List<String>.from(storage.getEventQueue());
    queue.add(event.encode());

    var overflow = 0;
    if (queue.length > maxQueueSize) {
      overflow = queue.length - maxQueueSize;
      queue.removeRange(0, overflow);
    }

    // Written before any other await. There is no suspension point between
    // reading the queue and writing it back, so a concurrent flush cannot
    // interleave and clobber a removal it already made.
    await storage.setEventQueue(queue);

    if (overflow > 0) {
      await storage.addDroppedEvents(overflow);
      SmartLinkLogger.warning(
        'Event queue full — dropped $overflow oldest event(s). '
        'Total dropped: ${storage.getDroppedEventCount()}',
      );
    }
  }

  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  bool _isValidEventName(String name) => _namePattern.hasMatch(name);

  // ── Flush ────────────────────────────────────────────────────────────────

  /// Send queued events now.
  ///
  /// Safe to call at any time: concurrent calls collapse into one, and a call
  /// during a backoff window is a no-op.
  Future<void> flush({bool force = false}) async {
    if (_disposed && !force) return;
    if (_flushing) return;

    if (!force && _nextAttemptAfter != null &&
        DateTime.now().isBefore(_nextAttemptAfter!)) {
      return;
    }

    _flushing = true;
    try {
      // Loop so a large backlog drains in several batches rather than one per
      // timer tick — but stop at the first failure so backoff still applies.
      while (true) {
        final queue = storage.getEventQueue();
        if (queue.isEmpty) break;

        final batchRaw = queue.take(batchSize).toList();
        final events = <TrackedEvent>[];
        final undecodable = <String>[];

        for (final raw in batchRaw) {
          final decoded = TrackedEvent.decode(raw);
          if (decoded == null) {
            undecodable.add(raw);
          } else {
            events.add(decoded);
          }
        }

        // A row we can't parse can never be sent. Drop it rather than let it
        // wedge the head of the queue.
        if (undecodable.isNotEmpty) {
          SmartLinkLogger.warning(
            'Discarded ${undecodable.length} unreadable queued event(s)',
          );
        }

        if (events.isEmpty) {
          await _removeFromQueue(batchRaw.length);
          continue;
        }

        final outcome = await _sendBatch(events);

        if (outcome.transportFailed) {
          await _onFlushFailure(batchRaw.length, events);
          break;
        }

        // Everything the server saw — accepted, duplicated, or permanently
        // rejected — leaves the queue. Only transient failures are retried.
        await _removeFromQueue(batchRaw.length);
        _onFlushSuccess();

        if (queue.length <= batchSize) break;
      }
    } catch (e) {
      SmartLinkLogger.debug('Flush error: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _removeFromQueue(int count) async {
    final queue = List<String>.from(storage.getEventQueue());
    if (count >= queue.length) {
      await storage.clearEventQueue();
    } else {
      await storage.setEventQueue(queue.sublist(count));
    }
  }

  void _onFlushSuccess() {
    _consecutiveFailures = 0;
    _nextAttemptAfter = null;
  }

  /// Back off, and bump each event's attempt counter so a permanently poisoned
  /// event eventually leaves the queue instead of blocking it forever.
  Future<void> _onFlushFailure(int batchLength, List<TrackedEvent> events) async {
    _consecutiveFailures++;

    // Exponential with jitter. Without jitter, every device that lost
    // connectivity at the same moment retries in lockstep when it returns.
    final baseMs = min(
      _maxBackoff.inMilliseconds,
      1000 * pow(2, min(_consecutiveFailures, 8)).toInt(),
    );
    final jitterMs = _random.nextInt(max(1, baseMs ~/ 4));
    _nextAttemptAfter =
        DateTime.now().add(Duration(milliseconds: baseMs + jitterMs));

    SmartLinkLogger.debug(
      'Flush failed (attempt $_consecutiveFailures) — retrying in '
      '${(baseMs + jitterMs) ~/ 1000}s',
    );

    // Awaited, not fire-and-forget: if the process dies before this write
    // lands, the event returns with its old count and a permanently
    // undeliverable event never ages out of the queue. It also races the
    // read-modify-write in track() and would lose whichever write finished
    // second.
    await _incrementAttempts(batchLength);
  }

  Future<void> _incrementAttempts(int count) async {
    try {
      final queue = List<String>.from(storage.getEventQueue());
      if (queue.isEmpty) return;

      final limit = min(count, queue.length);
      final rewritten = <String>[];
      var expired = 0;

      for (var i = 0; i < limit; i++) {
        final event = TrackedEvent.decode(queue[i]);
        if (event == null) continue;

        final next = event.copyWith(attempts: event.attempts + 1);
        if (next.attempts >= maxAttemptsPerEvent) {
          expired++;
          continue; // dropped
        }
        rewritten.add(next.encode());
      }

      if (expired > 0) {
        await storage.addDroppedEvents(expired);
        SmartLinkLogger.warning(
          'Dropped $expired event(s) after $maxAttemptsPerEvent failed attempts',
        );
      }

      await storage.setEventQueue([...rewritten, ...queue.sublist(limit)]);
    } catch (e) {
      SmartLinkLogger.debug('Failed to update retry counters: $e');
    }
  }

  // ── Transport ────────────────────────────────────────────────────────────

  Future<_SendOutcome> _sendBatch(List<TrackedEvent> events) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('${config.apiBaseUrl}/api/v1/events'),
            headers: config.getHeaders(),
            body: jsonEncode({
              'events': events.map((e) => e.toApiJson()).toList(),
            }),
          )
          .timeout(Duration(seconds: config.requestTimeoutSeconds));

      // 200 and 207 both mean the server processed the batch and returned a
      // per-event verdict. 207 just means some events were rejected on their
      // own merits — resending them would only be rejected again.
      if (response.statusCode == 200 || response.statusCode == 207) {
        _logRejections(response.body);
        return const _SendOutcome(transportFailed: false);
      }

      // 4xx other than 429 means the request itself is wrong — a bad key, a
      // malformed body. Retrying identical bytes cannot help.
      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 429) {
        SmartLinkLogger.warning(
          'Event batch rejected (${response.statusCode}) — discarding. '
          'Check your API key and SDK version.',
        );
        return const _SendOutcome(transportFailed: false);
      }

      // 429 and 5xx are transient — keep the events and back off.
      SmartLinkLogger.debug('Event batch deferred (${response.statusCode})');
      return const _SendOutcome(transportFailed: true);
    } on TimeoutException {
      return const _SendOutcome(transportFailed: true);
    } catch (e) {
      SmartLinkLogger.debug('Event batch send failed: $e');
      return const _SendOutcome(transportFailed: true);
    }
  }

  /// Surface per-event rejections in debug builds — a name typo or an oversized
  /// property should be obvious during integration, not discovered in a report.
  void _logRejections(String body) {
    try {
      final decoded = jsonDecode(body);
      final results = decoded?['data']?['results'];
      if (results is! List) return;

      for (final r in results) {
        if (r is! Map) continue;
        if (r['accepted'] == true) {
          final warnings = r['warnings'];
          if (warnings is List && warnings.isNotEmpty) {
            SmartLinkLogger.debug('Event accepted with warnings: $warnings');
          }
          continue;
        }
        final error = r['error'];
        if (error is Map) {
          SmartLinkLogger.warning(
            'Event rejected [${error['code']}]: ${error['message']}',
          );
        }
      }
    } catch (_) {
      // Diagnostics only.
    }
  }

  // ── Identity ─────────────────────────────────────────────────────────────

  /// Attach this device to a user.
  ///
  /// Queued events are flushed first: they were produced by this same person
  /// before they signed in, and flushing now means the server backfills them in
  /// the same transition rather than leaving them anonymous. The call is
  /// persisted, so signing in offline still identifies the user once
  /// connectivity returns.
  Future<bool> identify(
    String userId, {
    Map<String, dynamic>? traits,
    String? email,
  }) async {
    final deviceId = _cachedDeviceId ?? storage.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      SmartLinkLogger.warning('identify() skipped — no device id yet');
      return false;
    }

    await storage.setUserId(userId);

    final payload = {
      'userId': userId,
      'deviceId': deviceId,
      'platform': DeviceInfoHelper.getOsName(),
      if (traits != null && traits.isNotEmpty) 'traits': traits,
      if (email != null) 'email': email,
    };

    // Persist before sending. If the request dies mid-flight we replay rather
    // than lose the sign-in.
    await storage.setPendingIdentify(jsonEncode(payload));

    // Send anything already queued so the server's backfill sees it as this
    // user's pre-sign-in history.
    await flush();

    final sent = await _postIdentify(payload);
    if (sent) {
      await storage.clearPendingIdentify();
      await track('user_identified');
    }
    return sent;
  }

  Future<bool> _postIdentify(Map<String, dynamic> payload) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('${config.apiBaseUrl}/api/v1/identify'),
            headers: config.getHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.requestTimeoutSeconds));

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body)?['data'];
          final acquisition = data?['acquisition'];
          if (acquisition != null) {
            SmartLinkLogger.info(
              'Identified ${payload['userId']} — acquired via '
              '${acquisition['campaign'] ?? acquisition['shortCode'] ?? 'unknown'} '
              '(${acquisition['model']}), '
              '${data['backfilledEvents'] ?? 0} events backfilled',
            );
          } else {
            SmartLinkLogger.info('Identified ${payload['userId']}');
          }
        } catch (_) {}
        return true;
      }

      // A 4xx here is a rejected payload — replaying it would fail identically.
      if (response.statusCode >= 400 && response.statusCode < 500) {
        SmartLinkLogger.warning(
          'identify() rejected (${response.statusCode}) — not retrying',
        );
        await storage.clearPendingIdentify();
        return false;
      }

      SmartLinkLogger.debug('identify() deferred (${response.statusCode})');
      return false;
    } catch (e) {
      SmartLinkLogger.debug('identify() failed, will replay: $e');
      return false;
    }
  }

  Future<void> _replayPendingIdentify() async {
    final pending = storage.getPendingIdentify();
    if (pending == null) return;

    try {
      final payload = jsonDecode(pending);
      if (payload is! Map) {
        await storage.clearPendingIdentify();
        return;
      }
      SmartLinkLogger.debug('Replaying pending identify()');
      final sent = await _postIdentify(payload.cast<String, dynamic>());
      if (sent) await storage.clearPendingIdentify();
    } catch (_) {
      await storage.clearPendingIdentify();
    }
  }

  /// End the session on this device.
  ///
  /// Keeps the device id — rotating it would sever install attribution and make
  /// the next launch look like a new install. The server bumps an identity
  /// epoch instead, which is what stops the next person signing in on this
  /// device from inheriting this user's history.
  Future<bool> logout() async {
    final deviceId = _cachedDeviceId ?? storage.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) return false;

    // Flush first: events produced before logout belong to the user who is
    // leaving, and the server stamps them from the device's current state.
    await flush();
    await track('user_logged_out');
    await flush();

    await storage.clearUserId();
    await storage.clearPendingIdentify();

    // Start a fresh session so the next person doesn't continue this one.
    await storage.setSessionId(const Uuid().v4());
    await storage.setSessionLastActive(DateTime.now());

    try {
      final response = await _httpClient
          .post(
            Uri.parse('${config.apiBaseUrl}/api/v1/identify/logout'),
            headers: config.getHeaders(),
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(Duration(seconds: config.requestTimeoutSeconds));

      if (response.statusCode == 200) {
        SmartLinkLogger.info('Logged out');
        return true;
      }
      SmartLinkLogger.debug('logout() returned ${response.statusCode}');
      return false;
    } catch (e) {
      SmartLinkLogger.debug('logout() failed: $e');
      return false;
    }
  }

  /// The user id this device is currently signed in as, if any.
  String? get currentUserId => storage.getUserId();

  /// Events still waiting to be sent.
  int get queuedEventCount => storage.getEventQueue().length;

  /// Events discarded because the queue overflowed or exhausted its retries.
  int get droppedEventCount => storage.getDroppedEventCount();

  /// Replace the HTTP client. Test seam.
  set httpClient(http.Client client) {
    _httpClient.close();
    _httpClient = client;
  }
}

class _SendOutcome {
  /// True when the batch never got a verdict — a timeout, a 5xx, or a 429.
  /// Only these are retried; a per-event rejection is final.
  final bool transportFailed;

  const _SendOutcome({required this.transportFailed});
}
