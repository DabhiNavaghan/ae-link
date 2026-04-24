import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing local storage using SharedPreferences
class StorageService {
  static const String _keyFirstLaunch = 'smartlink_first_launch';
  static const String _keyDeviceId = 'smartlink_device_id';
  static const String _keyLastDeferredLinkCheck = 'smartlink_last_deferred_link_check';
  static const String _keyLastDeferredLink = 'smartlink_last_deferred_link';
  static const String _keyLastDeepLink = 'smartlink_last_deep_link';

  late SharedPreferences _prefs;

  /// Initialize storage service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Check if this is the first launch after app install.
  /// Read-only — does NOT mark as done. Call [markFirstLaunchComplete]
  /// after you've finished the deferred link check.
  Future<bool> isFirstLaunch() async {
    final value = _prefs.getBool(_keyFirstLaunch);
    // null means never set = first launch
    return value == null || value == true;
  }

  /// Mark first launch as complete
  Future<void> markFirstLaunchComplete() async {
    await _prefs.setBool(_keyFirstLaunch, false);
  }

  /// Get stored device ID
  String? getDeviceId() {
    return _prefs.getString(_keyDeviceId);
  }

  /// Save device ID
  Future<void> setDeviceId(String deviceId) async {
    await _prefs.setString(_keyDeviceId, deviceId);
  }

  /// Get timestamp of last deferred link check
  DateTime? getLastDeferredLinkCheckTime() {
    final timestamp = _prefs.getString(_keyLastDeferredLinkCheck);
    if (timestamp != null) {
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Save deferred link check timestamp
  Future<void> setLastDeferredLinkCheckTime(DateTime time) async {
    await _prefs.setString(_keyLastDeferredLinkCheck, time.toIso8601String());
  }

  /// Get last deferred link data (JSON string)
  String? getLastDeferredLink() {
    return _prefs.getString(_keyLastDeferredLink);
  }

  /// Save last deferred link data (JSON string)
  Future<void> setLastDeferredLink(String linkDataJson) async {
    await _prefs.setString(_keyLastDeferredLink, linkDataJson);
  }

  /// Clear last deferred link data
  Future<void> clearLastDeferredLink() async {
    await _prefs.remove(_keyLastDeferredLink);
  }

  /// Get last deep link data (JSON string)
  String? getLastDeepLink() {
    return _prefs.getString(_keyLastDeepLink);
  }

  /// Save last deep link data (JSON string)
  Future<void> setLastDeepLink(String linkDataJson) async {
    await _prefs.setString(_keyLastDeepLink, linkDataJson);
  }

  /// Clear all AE-LINK data
  Future<void> clearAll() async {
    await _prefs.remove(_keyFirstLaunch);
    await _prefs.remove(_keyDeviceId);
    await _prefs.remove(_keyLastDeferredLinkCheck);
    await _prefs.remove(_keyLastDeferredLink);
    await _prefs.remove(_keyLastDeepLink);
  }

  /// Check if more than N hours have passed since last deferred link check
  bool shouldCheckDeferredLink({int hoursThreshold = 24}) {
    final lastCheck = getLastDeferredLinkCheckTime();
    if (lastCheck == null) {
      return true; // Never checked, should check now
    }
    final now = DateTime.now();
    final difference = now.difference(lastCheck).inHours;
    return difference >= hoursThreshold;
  }
}
