import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlink/src/services/link_domain_registry.dart';
import 'package:smartlink/src/services/storage_service.dart';

const _base = 'https://smartlink.apps.allevents.app';

LinkDomainRegistry registry({
  String apiBaseUrl = _base,
  List<String> configured = const [],
}) =>
    LinkDomainRegistry(apiBaseUrl: apiBaseUrl, configuredDomains: configured);

/// Apply a server list without touching storage.
Future<LinkDomainRegistry> withServerDomains(List<String> domains,
    {String apiBaseUrl = _base}) async {
  final r = registry(apiBaseUrl: apiBaseUrl);
  await r.applyServerDomains(domains, cacheNamespace: 'test');
  return r;
}

void main() {
  group('nothing tenant-specific is compiled in', () {
    test('a fresh registry trusts only the configured apiBaseUrl host', () {
      final r = registry();
      expect(r.isSmartLinkHost('smartlink.apps.allevents.app'), isTrue);
      // Not known until the backend says so.
      expect(r.isSmartLinkHost('allevents.aelinks.io'), isFalse);
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isFalse);
      expect(r.isMinimal, isTrue);
    });

    test('trustedDomains leaks nothing before the server answers', () {
      expect(registry().trustedDomains, ['smartlink.apps.allevents.app']);
    });
  });

  group('server-issued domains', () {
    test('subdomains become first-party once the backend sends them', () async {
      final r = await withServerDomains(
          ['allevents.aelinks.io', 'organizer.aelinks.io']);
      expect(
        r.isSmartLinkUrl(Uri.parse('https://allevents.aelinks.io/xGJEQJR')),
        isTrue,
      );
      expect(
        r.isSmartLinkUrl(Uri.parse('https://organizer.aelinks.io/abc123')),
        isTrue,
      );
      expect(r.isMinimal, isFalse);
    });

    test('a wildcard entry covers subdomains added later', () async {
      final r = await withServerDomains(['*.aelinks.io']);
      expect(r.isSmartLinkHost('tickets.aelinks.io'), isTrue);
      expect(r.isSmartLinkHost('aelinks.io'), isTrue);
    });

    test('the apiBaseUrl host stays trusted alongside the server list', () async {
      final r = await withServerDomains(['organizer.aelinks.io']);
      expect(r.isSmartLinkHost('smartlink.apps.allevents.app'), isTrue);
    });

    test('an empty server list does not wipe a restored list', () async {
      final r = await withServerDomains(['organizer.aelinks.io']);
      await r.applyServerDomains(const [], cacheNamespace: 'test');
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isTrue);
    });

    test('a null server list is a no-op', () async {
      final r = await withServerDomains(['organizer.aelinks.io']);
      await r.applyServerDomains(null, cacheNamespace: 'test');
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isTrue);
    });

    test('another tenant\'s host is not trusted', () async {
      final r = await withServerDomains(['organizer.aelinks.io']);
      expect(r.isSmartLinkHost('someoneelse.aelinks.io'), isFalse);
    });
  });

  group('unsafe entries are refused client-side', () {
    test('a bare TLD is discarded', () async {
      final r = await withServerDomains(['com', 'io']);
      expect(r.isSmartLinkHost('example.com'), isFalse);
      expect(r.isMinimal, isTrue);
    });

    test('a wildcard on a TLD is discarded', () async {
      final r = await withServerDomains(['*.com']);
      expect(r.isSmartLinkHost('evil.com'), isFalse);
      expect(r.isMinimal, isTrue);
    });

    test('entries with a scheme, path, or empty label are discarded', () async {
      final r = await withServerDomains(
          ['..aelinks.io', 'foo bar.com', 'http://', '-lead.com', 'trail-.com']);
      expect(r.isMinimal, isTrue);
    });

    test('good entries survive alongside bad ones', () async {
      final r = await withServerDomains(['*.com', 'organizer.aelinks.io']);
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isTrue);
      expect(r.isSmartLinkHost('evil.com'), isFalse);
    });

    test('localhost is allowed but never as a wildcard', () async {
      expect((await withServerDomains(['localhost']))
          .isSmartLinkHost('localhost'), isTrue);
      expect((await withServerDomains(['*.localhost']))
          .isSmartLinkHost('any.localhost'), isFalse);
    });
  });

  group('look-alike hosts stay external', () {
    late LinkDomainRegistry r;
    setUp(() async {
      r = await withServerDomains(['*.aelinks.io', 'organizer.aelinks.io']);
    });

    test('a suffix that is not a label boundary does not match', () {
      expect(r.isSmartLinkHost('evil-aelinks.io'), isFalse);
      expect(r.isSmartLinkHost('notaelinks.io'), isFalse);
    });

    test('our domain as a prefix of an attacker domain does not match', () {
      expect(r.isSmartLinkHost('aelinks.io.attacker.com'), isFalse);
      expect(r.isSmartLinkHost('organizer.aelinks.io.attacker.com'), isFalse);
    });

    test('unrelated hosts, custom schemes and blanks are external', () {
      expect(r.isSmartLinkUrl(Uri.parse('https://example.com/xGJEQJR')), isFalse);
      expect(r.isSmartLinkUrl(Uri.parse('myapp://event/123')), isFalse);
      expect(r.isSmartLinkHost(null), isFalse);
      expect(r.isSmartLinkHost(''), isFalse);
    });
  });

  group('normalization', () {
    test('casing and a trailing root dot are handled', () async {
      final r = await withServerDomains(['Organizer.AELinks.IO']);
      expect(r.isSmartLinkHost('ORGANIZER.aelinks.io'), isTrue);
      expect(r.isSmartLinkHost('organizer.aelinks.io.'), isTrue);
    });

    test('a full URL entry is reduced to its host', () async {
      final r = await withServerDomains(['https://organizer.aelinks.io/path']);
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isTrue);
    });

    test('duplicates collapse', () async {
      final r = await withServerDomains(
          ['organizer.aelinks.io', 'ORGANIZER.aelinks.io.']);
      expect(r.trustedDomains.where((d) => d.contains('organizer')).length, 1);
    });

    test('a base URL with a port matches on host alone', () {
      final r = registry(apiBaseUrl: 'http://localhost:3000');
      expect(r.isSmartLinkUrl(Uri.parse('http://localhost:3000/abc123')), isTrue);
    });
  });

  group('configured override', () {
    test('a self-hosted domain works without the server', () {
      final r = registry(configured: ['links.mybrand.com', '*.mybrand.io']);
      expect(r.isSmartLinkHost('links.mybrand.com'), isTrue);
      expect(r.isSmartLinkHost('go.mybrand.io'), isTrue);
      expect(r.isSmartLinkHost('other.links.mybrand.com'), isFalse);
      expect(r.isMinimal, isFalse);
    });

    test('an unsafe override is refused too', () {
      final r = registry(configured: ['*.com', '']);
      expect(r.isSmartLinkHost('evil.com'), isFalse);
      expect(r.isMinimal, isTrue);
    });
  });

  group('cache namespace', () {
    test('differs per API key and per base URL', () {
      final a = LinkDomainRegistry.cacheNamespaceFor(
          apiKey: 'key-a', apiBaseUrl: _base);
      final b = LinkDomainRegistry.cacheNamespaceFor(
          apiKey: 'key-b', apiBaseUrl: _base);
      final c = LinkDomainRegistry.cacheNamespaceFor(
          apiKey: 'key-a', apiBaseUrl: 'https://other.example.com');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('is stable for the same credentials', () {
      expect(
        LinkDomainRegistry.cacheNamespaceFor(apiKey: 'k', apiBaseUrl: _base),
        LinkDomainRegistry.cacheNamespaceFor(apiKey: 'k', apiBaseUrl: _base),
      );
    });

    test('does not contain the API key', () {
      final ns = LinkDomainRegistry.cacheNamespaceFor(
          apiKey: 'super-secret-key', apiBaseUrl: _base);
      expect(ns.contains('super-secret-key'), isFalse);
      expect(ns, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('cache payload', () {
    test('a stale entry is not trusted', () async {
      final storage = _FakeStorage();
      final stale = DateTime.now().subtract(const Duration(days: 45));
      storage.store['smartlink_link_domains_ns'] = jsonEncode({
        'cachedAt': stale.millisecondsSinceEpoch,
        'domains': ['organizer.aelinks.io'],
      });
      final r = LinkDomainRegistry(
          apiBaseUrl: _base, storageService: storage);
      await r.restoreFromCache(cacheNamespace: 'ns');
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isFalse);
      expect(storage.store.containsKey('smartlink_link_domains_ns'), isFalse);
    });

    test('a fresh entry is restored', () async {
      final storage = _FakeStorage();
      storage.store['smartlink_link_domains_ns'] = jsonEncode({
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'domains': ['organizer.aelinks.io'],
      });
      final r = LinkDomainRegistry(
          apiBaseUrl: _base, storageService: storage);
      await r.restoreFromCache(cacheNamespace: 'ns');
      expect(r.isSmartLinkHost('organizer.aelinks.io'), isTrue);
    });

    test('a corrupt entry is dropped rather than throwing', () async {
      final storage = _FakeStorage();
      storage.store['smartlink_link_domains_ns'] = 'not json at all';
      final r = LinkDomainRegistry(
          apiBaseUrl: _base, storageService: storage);
      await r.restoreFromCache(cacheNamespace: 'ns');
      expect(r.isMinimal, isTrue);
      expect(storage.store.containsKey('smartlink_link_domains_ns'), isFalse);
    });

    test('applying a server list writes it back to the cache', () async {
      final storage = _FakeStorage();
      final r = LinkDomainRegistry(
          apiBaseUrl: _base, storageService: storage);
      await r.applyServerDomains(['organizer.aelinks.io'],
          cacheNamespace: 'ns');
      final payload =
          jsonDecode(storage.store['smartlink_link_domains_ns']!) as Map;
      expect(payload['domains'], ['organizer.aelinks.io']);
    });
  });
}

/// Minimal StorageService stand-in — only the link-domain methods are used.
class _FakeStorage implements StorageServiceLinkDomains {
  final Map<String, String> store = {};

  @override
  String? getLinkDomains(String namespace) =>
      store['smartlink_link_domains_$namespace'];

  @override
  Future<void> setLinkDomains(String namespace, String payload) async {
    store['smartlink_link_domains_$namespace'] = payload;
  }

  @override
  Future<void> clearLinkDomains(String namespace) async {
    store.remove('smartlink_link_domains_$namespace');
  }
}
