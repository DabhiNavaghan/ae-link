import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlink/src/config.dart';
import 'package:smartlink/src/models/tracked_event.dart';
import 'package:smartlink/src/services/storage_service.dart';
import 'package:smartlink/src/services/tracking_service.dart';

/// A stub client that records requests and replays scripted responses.
///
/// The queue's contract is "nothing is lost that the server never saw", so the
/// tests below mostly assert what survives in storage after a given response.
class _StubClient extends http.BaseClient {
  _StubClient(this.responder);

  final http.Response Function(http.Request request) responder;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requests.add(req);
    final res = responder(req);
    return http.StreamedResponse(
      Stream.value(utf8.encode(res.body)),
      res.statusCode,
      headers: res.headers,
    );
  }

  /// The events in the Nth request body.
  List<Map<String, dynamic>> eventsIn(int index) {
    final body = jsonDecode(requests[index].body) as Map<String, dynamic>;
    return (body['events'] as List).cast<Map<String, dynamic>>();
  }
}

http.Response _ok(int accepted) => http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'results': List.generate(
            accepted,
            (i) => {'index': i, 'accepted': true, 'eventId': 'e$i'},
          ),
          'accepted': accepted,
          'rejected': 0,
          'duplicates': 0,
        },
      }),
      200,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late SmartLinkConfig config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    await storage.setDeviceId('device-1');
    config = SmartLinkConfig(
      tenantApiKey: 'app_test',
      apiBaseUrl: 'https://example.test',
      requestTimeoutSeconds: 5,
    );
  });

  TrackingService serviceWith(_StubClient client) {
    final service = TrackingService(config: config, storage: storage);
    service.httpClient = client;
    return service;
  }

  group('track', () {
    test('persists the event to disk so it survives a cold start', () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      await service.track('ticket_purchase', value: 1250, currency: 'INR');

      final queue = storage.getEventQueue();
      expect(queue, hasLength(1));

      final decoded = TrackedEvent.decode(queue.first)!;
      expect(decoded.name, 'ticket_purchase');
      expect(decoded.value, 1250);
      expect(decoded.currency, 'INR');
      expect(decoded.deviceId, 'device-1');
      expect(decoded.idempotencyKey, isNotEmpty);
    });

    test('rejects an invalid event name without queueing it', () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      await service.track('Ticket Purchase');
      await service.track('9lives');
      await service.track('');

      expect(storage.getEventQueue(), isEmpty);
    });

    test('gives every event a distinct idempotency key', () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      await service.track('app_open');
      await service.track('app_open');

      final keys = storage
          .getEventQueue()
          .map((raw) => TrackedEvent.decode(raw)!.idempotencyKey)
          .toSet();
      expect(keys, hasLength(2));
    });

    test('drops oldest-first when the queue is full, and counts the loss',
        () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      // Seed a full queue directly — tracking 1000 events through the public
      // API would also trigger flushes.
      final seeded = List.generate(
        TrackingService.maxQueueSize,
        (i) => TrackedEvent(
          name: 'seeded_$i'.substring(0, 8),
          occurredAt: DateTime(2026, 1, 1).add(Duration(seconds: i)),
          idempotencyKey: 'key-$i',
        ).encode(),
      );
      await storage.setEventQueue(seeded);

      final oldestBefore = TrackedEvent.decode(seeded.first)!.idempotencyKey;

      await service.track('newest_event');

      final queue = storage.getEventQueue();
      expect(queue, hasLength(TrackingService.maxQueueSize));
      expect(
        queue.map((r) => TrackedEvent.decode(r)!.idempotencyKey),
        isNot(contains(oldestBefore)),
        reason: 'the oldest event should have been evicted',
      );
      expect(storage.getDroppedEventCount(), 1);
    });
  });

  group('flush', () {
    test('sends queued events and clears them on success', () async {
      final client = _StubClient((_) => _ok(2));
      final service = serviceWith(client);

      await service.track('app_open');
      await service.track('session_start');
      await service.flush(force: true);

      expect(client.requests, hasLength(1));
      expect(client.eventsIn(0).map((e) => e['name']),
          containsAll(['app_open', 'session_start']));
      expect(storage.getEventQueue(), isEmpty);
    });

    test('keeps events queued when the server is unreachable', () async {
      final client = _StubClient(
        (_) => http.Response('{"error":"boom"}', 503),
      );
      final service = serviceWith(client);

      await service.track('ticket_purchase', value: 500);
      await service.flush(force: true);

      expect(storage.getEventQueue(), hasLength(1),
          reason: 'a 5xx is transient — the event must be retried, not lost');
    });

    test('discards events the server permanently rejected', () async {
      // A 400 means the request itself is wrong. Resending identical bytes
      // would be rejected identically, so retrying forever is pure waste.
      final client = _StubClient(
        (_) => http.Response('{"error":"bad request"}', 400),
      );
      final service = serviceWith(client);

      await service.track('app_open');
      await service.flush(force: true);

      expect(storage.getEventQueue(), isEmpty);
    });

    test('clears the queue on a 207 — per-event verdicts are final', () async {
      final client = _StubClient(
        (_) => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'results': [
                {'index': 0, 'accepted': true, 'eventId': 'e0'},
                {
                  'index': 1,
                  'accepted': false,
                  'error': {'code': 'INVALID_NAME', 'message': 'bad'}
                },
              ],
              'accepted': 1,
              'rejected': 1,
              'duplicates': 0,
            },
          }),
          207,
        ),
      );
      final service = serviceWith(client);

      await service.track('app_open');
      await service.track('app_install');
      await service.flush(force: true);

      expect(storage.getEventQueue(), isEmpty);
    });

    test('backs off after a failure instead of hammering the server', () async {
      final client = _StubClient((_) => http.Response('{}', 500));
      final service = serviceWith(client);

      await service.track('app_open');
      await service.flush(force: true);
      expect(client.requests, hasLength(1));

      // A non-forced flush inside the backoff window must be a no-op.
      await service.flush();
      expect(client.requests, hasLength(1));
    });

    test('drops an event that has exhausted its retries', () async {
      final client = _StubClient((_) => http.Response('{}', 500));
      final service = serviceWith(client);

      await storage.setEventQueue([
        TrackedEvent(
          name: 'poisoned',
          occurredAt: DateTime(2026, 1, 1),
          idempotencyKey: 'poison-key',
          attempts: TrackingService.maxAttemptsPerEvent - 1,
        ).encode(),
      ]);

      await service.flush(force: true);

      expect(storage.getEventQueue(), isEmpty,
          reason: 'one undeliverable event must not block the queue forever');
      expect(storage.getDroppedEventCount(), 1);
    });

    test('discards an unreadable queue entry rather than wedging', () async {
      final client = _StubClient((_) => _ok(1));
      final service = serviceWith(client);

      await storage.setEventQueue(['not json at all']);
      await service.flush(force: true);

      expect(storage.getEventQueue(), isEmpty);
      expect(client.requests, isEmpty,
          reason: 'nothing sendable was in the batch');
    });
  });

  group('sessions', () {
    test('reuses the session id while the app stays active', () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      final first = await service.currentSessionId();
      final second = await service.currentSessionId();

      expect(second, first);
    });

    test('starts a new session after the inactivity timeout', () async {
      final service = serviceWith(_StubClient((_) => _ok(1)));

      final first = await service.currentSessionId();

      await storage.setSessionLastActive(
        DateTime.now().subtract(TrackingService.sessionTimeout * 2),
      );
      expect(service.sessionExpired, isTrue);

      final second = await service.currentSessionId();
      expect(second, isNot(first));
    });
  });

  group('identify', () {
    test('flushes queued events before identifying, so they get backfilled',
        () async {
      final paths = <String>[];
      final client = _StubClient((req) {
        paths.add(req.url.path);
        return req.url.path == '/api/v1/identify'
            ? http.Response(
                jsonEncode({
                  'success': true,
                  'data': {
                    'userId': 'u_1',
                    'epoch': 1,
                    'isNewIdentity': true,
                    'backfilledEvents': 2,
                    'acquisition': {'model': 'install_match', 'campaign': 'diwali'},
                  },
                }),
                200,
              )
            : _ok(2);
      });
      final service = serviceWith(client);

      await service.track('app_open');
      await service.track('app_install');

      final ok = await service.identify('u_1', traits: {'plan': 'pro'});

      expect(ok, isTrue);
      expect(paths.first, '/api/v1/events',
          reason: 'pre-sign-in events must reach the server before identify');
      expect(paths, contains('/api/v1/identify'));
      expect(service.currentUserId, 'u_1');
      expect(storage.getPendingIdentify(), isNull);
    });

    test('persists the call for replay when the server is unreachable',
        () async {
      final client = _StubClient((req) => req.url.path == '/api/v1/identify'
          ? http.Response('{}', 503)
          : _ok(1));
      final service = serviceWith(client);

      final ok = await service.identify('u_2');

      expect(ok, isFalse);
      expect(storage.getPendingIdentify(), isNotNull,
          reason: 'a user who signs in offline must still be identified later');
      // The user id is remembered locally regardless, so the app can read it back.
      expect(service.currentUserId, 'u_2');
    });

    test('does not replay a call the server rejected outright', () async {
      final client = _StubClient((req) => req.url.path == '/api/v1/identify'
          ? http.Response('{}', 400)
          : _ok(1));
      final service = serviceWith(client);

      await service.identify('u_3');

      expect(storage.getPendingIdentify(), isNull);
    });
  });

  group('logout', () {
    test('keeps the device id and starts a fresh session', () async {
      final client = _StubClient((_) => _ok(1));
      final service = serviceWith(client);

      await service.identify('u_1');
      final sessionBefore = await service.currentSessionId();

      await service.logout();

      expect(storage.getDeviceId(), 'device-1',
          reason: 'rotating the device id would sever install attribution');
      expect(service.currentUserId, isNull);
      expect(storage.getSessionId(), isNot(sessionBefore));
    });
  });
}
