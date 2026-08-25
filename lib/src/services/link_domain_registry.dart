import 'dart:convert';

import '../utils/logger.dart';
import 'storage_service.dart';

/// Decides whether an incoming URL is one of *our* SmartLinks or an external
/// deep link.
///
/// The list of link hosts is **not** compiled into the SDK. It is issued by the
/// backend at init, scoped to the app whose API key authenticated, and cached
/// on device so a cold start does not have to wait for the network. That keeps
/// the SDK tenant-agnostic and keeps one tenant's domains out of another
/// tenant's app binary.
///
/// Trust sources, in order:
///   1. `apiBaseUrl`'s host — always trusted; the integrator configured it.
///   2. `linkDomains` from [SmartLinkConfig] — an explicit integrator override,
///      for self-hosted deployments that cannot rely on the server list.
///   3. Server-issued domains from `/api/v1/sdk/init`, cached locally.
///
/// Matching mirrors `lib/utils/link-domain-match.ts` on the backend so both
/// sides classify a link identically.
class LinkDomainRegistry {
  LinkDomainRegistry({
    required String apiBaseUrl,
    List<String> configuredDomains = const [],
    StorageServiceLinkDomains? storageService,
  })  : _storageService = storageService,
        _baseHost = toBareHost(apiBaseUrl) {
    _configuredDomains = _sanitize(configuredDomains);
  }

  final StorageServiceLinkDomains? _storageService;

  /// Host of the configured `apiBaseUrl`. Always trusted, never persisted —
  /// it is re-derived from config on every launch.
  final String _baseHost;

  /// Explicit overrides from [SmartLinkConfig.linkDomains].
  late final List<String> _configuredDomains;

  /// Domains handed down by the backend (or restored from cache).
  List<String> _serverDomains = const [];

  /// Whether a server list has been applied or restored this run.
  bool _hasServerDomains = false;

  /// A cached list older than this is discarded rather than trusted. Long
  /// enough to survive a device being offline for a while, short enough that a
  /// domain removed in the dashboard stops being honoured.
  static const Duration _maxCacheAge = Duration(days: 30);

  /// Longest plausible hostname; anything beyond it is malformed.
  static const int _maxHostLength = 253;

  /// Whether the registry is running on `apiBaseUrl` alone — i.e. no server
  /// list and no configured override. Deep links still work for the API host;
  /// short-link subdomains do not until init succeeds once.
  bool get isMinimal => !_hasServerDomains && _configuredDomains.isEmpty;

  /// Every domain currently trusted. Exposed for diagnostics and tests.
  List<String> get trustedDomains => [
        if (_baseHost.isNotEmpty) _baseHost,
        ..._configuredDomains,
        ..._serverDomains,
      ];

  // ── Matching ──────────────────────────────────────────────────────

  /// Whether [host] belongs to one of our link domains.
  bool isSmartLinkHost(String? host) {
    final target = toBareHost(host ?? '');
    if (target.isEmpty) return false;

    if (_baseHost.isNotEmpty && target == _baseHost) return true;
    return _matchesAny(target, _configuredDomains) ||
        _matchesAny(target, _serverDomains);
  }

  /// Whether [uri] points at one of our link domains.
  bool isSmartLinkUrl(Uri uri) => isSmartLinkHost(uri.host);

  static bool _matchesAny(String target, List<String> domains) {
    for (final entry in domains) {
      if (entry.startsWith('*.')) {
        final base = entry.substring(2);
        // Anchored on a label boundary: given `*.example.com`, neither
        // `evil-example.com` nor `example.com.attacker.com` matches.
        if (target == base || target.endsWith('.$base')) return true;
      } else if (target == entry) {
        return true;
      }
    }
    return false;
  }

  // ── Server list ───────────────────────────────────────────────────

  /// Apply the domain list returned by `/api/v1/sdk/init` and cache it.
  ///
  /// A null or empty list is treated as "the server told us nothing useful"
  /// and leaves any restored cache in place, so a partial response cannot
  /// silently downgrade a working install to external-only.
  Future<void> applyServerDomains(
    List<String>? domains, {
    required String cacheNamespace,
  }) async {
    if (domains == null) return;

    final sanitized = _sanitize(domains);
    if (sanitized.isEmpty) {
      SmartLinkLogger.verbose('Init returned no usable link domains');
      return;
    }

    _serverDomains = sanitized;
    _hasServerDomains = true;
    SmartLinkLogger.verbose('Link domains loaded: ${sanitized.length} host(s)');

    await _persist(sanitized, cacheNamespace: cacheNamespace);
  }

  /// Restore the cached list so a cold start can classify links before — or
  /// without — a successful init call.
  Future<void> restoreFromCache({required String cacheNamespace}) async {
    final storage = _storageService;
    if (storage == null) return;

    final raw = storage.getLinkDomains(cacheNamespace);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final cachedAtMillis = decoded['cachedAt'];
      if (cachedAtMillis is! int) return;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(cachedAtMillis),
      );
      if (age.isNegative || age > _maxCacheAge) {
        await storage.clearLinkDomains(cacheNamespace);
        return;
      }

      final domains = decoded['domains'];
      if (domains is! List) return;

      final sanitized = _sanitize(domains.whereType<String>().toList());
      if (sanitized.isEmpty) return;

      _serverDomains = sanitized;
      _hasServerDomains = true;
      SmartLinkLogger.verbose(
        'Link domains restored from cache: ${sanitized.length} host(s)',
      );
    } catch (_) {
      // A corrupt entry is not worth failing init over — drop it and let the
      // init response repopulate the cache.
      await storage.clearLinkDomains(cacheNamespace);
    }
  }

  Future<void> _persist(
    List<String> domains, {
    required String cacheNamespace,
  }) async {
    final storage = _storageService;
    if (storage == null) return;
    try {
      await storage.setLinkDomains(
        cacheNamespace,
        jsonEncode({
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
          'domains': domains,
        }),
      );
    } catch (e) {
      SmartLinkLogger.verbose('Could not cache link domains: $e');
    }
  }

  // ── Normalization and safety ──────────────────────────────────────

  /// Normalize, validate and dedupe, preserving order.
  static List<String> _sanitize(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final entry = _normalizeEntry(item);
      if (entry.isEmpty) continue;
      if (seen.add(entry)) out.add(entry);
    }
    return List.unmodifiable(out);
  }

  /// Reduce one entry to a canonical `host` or `*.host`, or '' if unusable.
  static String _normalizeEntry(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return '';

    final isWildcard = trimmed.startsWith('*.');
    final host = toBareHost(isWildcard ? trimmed.substring(2) : trimmed);
    if (!_isSafeHost(host, isWildcard: isWildcard)) return '';

    return isWildcard ? '*.$host' : host;
  }

  /// Guard against an entry broad or malformed enough to make the SDK trust
  /// far too much — a bare TLD, a wildcard on a TLD, a host with empty labels.
  /// The backend applies the same rule; this is the client-side backstop for a
  /// bad config or a tampered response.
  static bool _isSafeHost(String host, {required bool isWildcard}) {
    if (host.isEmpty || host.length > _maxHostLength) return false;
    if (RegExp(r'[^a-z0-9.-]').hasMatch(host)) return false;

    final labels = host.split('.');
    for (final label in labels) {
      if (label.isEmpty || label.length > 63) return false;
      if (label.startsWith('-') || label.endsWith('-')) return false;
    }

    if (labels.length < 2) {
      // `localhost` is legitimate for local development; `com` / `*.io` would
      // hand an attacker every link under a public suffix.
      return !isWildcard && host == 'localhost';
    }
    return true;
  }

  /// Strip a URL, `host:port` or trailing root dot down to a bare hostname.
  static String toBareHost(String raw) {
    var host = raw.trim().toLowerCase();
    if (host.isEmpty) return '';
    if (host.contains('://')) {
      host = Uri.tryParse(host)?.host ?? '';
    }
    host = host.split('/').first.split(':').first;
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  /// A stable, non-reversible namespace for the on-device cache, derived from
  /// the credentials the list was issued for. Swapping API key or base URL
  /// therefore starts from a clean cache instead of reusing another
  /// tenant's domains.
  ///
  /// This namespaces an app-private store; it is not a security boundary and
  /// deliberately avoids adding a crypto dependency for it.
  static String cacheNamespaceFor({
    required String apiKey,
    required String apiBaseUrl,
  }) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;

    var hash = offset;
    for (final unit in utf8.encode('$apiKey|$apiBaseUrl')) {
      hash = (hash ^ unit) & mask;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
