import 'dart:async';
import 'package:app_links/app_links.dart';
import '../models/deep_link_data.dart';
import '../utils/logger.dart';

/// Service for handling incoming deep links via Universal Links / App Links
///
/// Compatible with app_links v3, v4, v5, and v6+ by using runtime
/// method resolution via noSuchMethod fallback.
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
      AeLinkLogger.info('Initializing deep link handler');

      // Check for initial link if app was opened from a deep link.
      // app_links v6 renamed getInitialAppLink() → getInitialLink().
      // Try both to support all versions.
      final initialUri = await _getInitialLink();
      if (initialUri != null) {
        AeLinkLogger.info('Initial deep link: $initialUri');
        _handleDeepLink(initialUri);
      }

      // Listen for subsequent deep links
      _deepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          AeLinkLogger.info('Deep link received: $uri');
          _handleDeepLink(uri);
        },
        onError: (err) {
          AeLinkLogger.error('Error listening to deep links', err);
        },
      );

      AeLinkLogger.info('Deep link handler initialized');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Error initializing deep link handler', e, stackTrace);
      rethrow;
    }
  }

  /// Get initial link — tries v3-5 API first, then v6+ API
  Future<Uri?> _getInitialLink() async {
    try {
      // v3/v4/v5: getInitialAppLink()
      return await _appLinks.getInitialAppLink();
    } on NoSuchMethodError {
      // v6+: getInitialAppLink was renamed to getInitialLink
      try {
        // Use dynamic call to avoid compile-time dependency on v6 API
        final dynamic links = _appLinks;
        return await links.getInitialLink() as Uri?;
      } catch (_) {
        return null;
      }
    } catch (e) {
      AeLinkLogger.debug('getInitialAppLink failed: $e');
      return null;
    }
  }

  /// Handle incoming deep link URI
  void _handleDeepLink(Uri uri) {
    try {
      AeLinkLogger.debug('Processing deep link: $uri');

      final deepLinkData = DeepLinkData.fromUrl(uri.toString());
      _deepLinkController.add(deepLinkData);

      AeLinkLogger.debug('Deep link processed: $deepLinkData');
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Error processing deep link', e, stackTrace);
    }
  }

  /// Manually process a deep link URL
  void processDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      _handleDeepLink(uri);
    } catch (e, stackTrace) {
      AeLinkLogger.errorWithStackTrace('Error processing deep link manually', e, stackTrace);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _deepLinkSubscription.cancel();
    await _deepLinkController.close();
    AeLinkLogger.info('Deep link handler disposed');
  }
}
