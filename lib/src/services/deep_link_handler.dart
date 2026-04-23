import 'dart:async';
import 'package:app_links/app_links.dart';
import '../models/deep_link_data.dart';
import '../utils/logger.dart';

/// Service for handling incoming deep links via Universal Links / App Links
///
/// Compatible with all app_links versions (v3 through v7+) by using
/// dynamic dispatch to avoid compile-time method resolution.
class DeepLinkHandler {
  final AppLinks _appLinks = AppLinks();
  late StreamSubscription<Uri> _deepLinkSubscription;
  final StreamController<DeepLinkData> _deepLinkController =
      StreamController<DeepLinkData>.broadcast();

  /// Get stream of deep links
  Stream<DeepLinkData> get onDeepLink => _deepLinkController.stream;

  /// Initialize deep link listener
  Future<void> initialize() async {
    try {
      // Check for initial link if app was opened from a deep link
      final initialUri = await _getInitialLink();
      if (initialUri != null) {
        AeLinkLogger.info('App opened via deep link: $initialUri');
        _handleDeepLink(initialUri);
      }

      // Listen for subsequent deep links
      _deepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          AeLinkLogger.info('Deep link received: $uri');
          _handleDeepLink(uri);
        },
        onError: (err) {
          AeLinkLogger.error('Deep link error', err);
        },
      );
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error initializing deep link handler', e, stackTrace);
      rethrow;
    }
  }

  /// Get initial link — works across all app_links versions.
  ///
  /// Uses fully dynamic calls so the compiler never checks method names.
  /// - v3/v4/v5: has getInitialAppLink()
  /// - v6: renamed to getInitialLink()
  /// - v7+: getInitialLink()
  Future<Uri?> _getInitialLink() async {
    final dynamic links = _appLinks;

    // Try v6+/v7+ method first (getInitialLink) since it's the latest
    try {
      final result = await links.getInitialLink();
      if (result != null) return result as Uri;
    } catch (_) {
      // Method doesn't exist in this version
    }

    // Fall back to v3-v5 method (getInitialAppLink)
    try {
      final result = await links.getInitialAppLink();
      if (result != null) return result as Uri;
    } catch (_) {
      // Method doesn't exist in this version either
    }

    return null;
  }

  /// Handle incoming deep link URI
  void _handleDeepLink(Uri uri) {
    try {
      AeLinkLogger.debug('Processing deep link: $uri');

      final deepLinkData = DeepLinkData.fromUrl(uri.toString());
      _deepLinkController.add(deepLinkData);

      AeLinkLogger.debug('Deep link processed: $deepLinkData');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error processing deep link', e, stackTrace);
    }
  }

  /// Manually process a deep link URL
  void processDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      _handleDeepLink(uri);
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace(
          'Error processing deep link manually', e, stackTrace);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _deepLinkSubscription.cancel();
    await _deepLinkController.close();
    AeLinkLogger.info('Deep link handler disposed');
  }
}
