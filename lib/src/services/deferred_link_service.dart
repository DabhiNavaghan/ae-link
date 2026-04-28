import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/deep_link_data.dart';
import '../models/device_fingerprint.dart';
import '../models/link_params.dart';
import '../utils/logger.dart';

/// Service for API calls related to deferred deep linking
class DeferredLinkService {
  final SmartLinkConfig config;
  late http.Client _httpClient;

  DeferredLinkService({required this.config}) {
    _httpClient = http.Client();
  }

  /// Match device fingerprint against stored deferred links
  ///
  /// The server identifies the tenant from the X-API-Key header,
  /// so we don't need to send tenantId in the body.
  Future<DeepLinkData?> matchFingerprint(DeviceFingerprint fingerprint) async {
    try {
      final url =
          Uri.parse('${config.apiBaseUrl}/api/v1/deferred/match');
      final body = jsonEncode({
        'fingerprint': fingerprint.toJson(),
      });

      final response = await _httpClient
          .post(
            url,
            headers: config.getHeaders(),
            body: body,
          )
          .timeout(
            Duration(seconds: config.requestTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                'Deferred link matching request timed out after ${config.requestTimeoutSeconds}s',
              );
            },
          );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

        if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
          final data = jsonResponse['data'] as Map<String, dynamic>;

          if (data['matched'] != true) {
            SmartLinkLogger.info('No deferred link matched (organic install)');
            return null;
          }

          SmartLinkLogger.info('✅ DEFERRED LINK MATCHED! Score: ${data['matchScore']}');
          return _parseDeepLinkResponse(data);
        }
      } else if (response.statusCode == 401) {
        SmartLinkLogger.warning('Unauthorized — check your API key');
        return null;
      } else {
        SmartLinkLogger.warning('Deferred match failed: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace('Error matching fingerprint', e, stackTrace);
      return null;
    }
    return null;
  }

  /// Confirm that a deferred link was shown to the user
  Future<bool> confirmDeepLink(String deferredLinkId) async {
    try {
      SmartLinkLogger.info('Confirming deferred link...');

      final url = Uri.parse('${config.apiBaseUrl}/api/v1/deferred/confirm');
      final body = jsonEncode({
        'deferredLinkId': deferredLinkId,
        'deviceId': config.tenantApiKey.hashCode.toString(),
      });

      final response = await _httpClient
          .post(
            url,
            headers: config.getHeaders(),
            body: body,
          )
          .timeout(
            Duration(seconds: config.requestTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                'Deferred link confirmation request timed out after ${config.requestTimeoutSeconds}s',
              );
            },
          );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final success = jsonResponse['success'] as bool? ?? false;
        if (success) {
          SmartLinkLogger.info('✅ Deferred link confirmed');
        }
        return success;
      } else {
        SmartLinkLogger.warning('Deferred link confirm failed');
        return false;
      }
    } catch (e, stackTrace) {
      SmartLinkLogger.errorWithStackTrace('Error confirming deferred link', e, stackTrace);
      return false;
    }
  }

  /// Parse deep link response from API
  ///
  /// The API returns camelCase keys:
  /// { matched, deferredLinkId, linkId, params, destinationUrl, matchScore }
  DeepLinkData _parseDeepLinkResponse(Map<String, dynamic> data) {
    final params = data['params'] as Map<String, dynamic>?;

    return DeepLinkData(
      linkId: data['linkId'] as String?,
      deferredLinkId: data['deferredLinkId'] as String?,
      eventId: params?['eventId'] as String?,
      action: params?['action'] as String?,
      destinationUrl: data['destinationUrl'] as String?,
      linkParams: params != null ? LinkParams.fromJson(params) : null,
      isDeferred: true,
      clickedAt: DateTime.now(),
    );
  }

  /// Dispose resources
  void dispose() {
    _httpClient.close();
  }
}

/// Exception for timeout errors
class TimeoutException implements Exception {
  final String message;

  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
