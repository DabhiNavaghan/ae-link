import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing local storage using SharedPreferences
class StorageService {
  static const String _keyFirstLaunch = 'smartlink_first_launch';
  static const String _keyDeviceId = 'smartlink_device_id';
  static const String _keyLastDeferredLinkCheck = 'smartlink_last_deferred_link_check';
  static const String _keyLastDeferredLink = 'smartlink_last_deferred_link';
  static const String _keyLastDeepLink = 'smartlink_last_deep_link';

  // ── Event tracking ──
  static const String _keyEventQueue = 'smartlink_event_queue';
  static const String _keyUserId = 'smartlink_user_id';
  static const String _keySessionId = 'smartlink_session_id';
  static const String _keySessionLastActive = 'smartlink_session_last_active';
  static const String _keyPendingIdentify = 'smartlink_pending_identify';
  static const String _keyDroppedEventCount = 'smartlink_dropped_events';

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

  // ── Event queue ────────────────────────────────────────────────────────
  //
  // Stored as a list of JSON strings rather than one blob so appending a single
  // event doesn't cost a full re-encode of the whole queue.

  /// The persisted event queue, oldest first.
  List<String> getEventQueue() {
    return _prefs.getStringList(_keyEventQueue) ?? const [];
  }

  Future<void> setEventQueue(List<String> events) async {
    await _prefs.setStringList(_keyEventQueue, events);
  }

  Future<void> clearEventQueue() async {
    await _prefs.remove(_keyEventQueue);
  }

  /// Events discarded because the queue was full. Reported as a diagnostic so
  /// silent data loss is at least visible.
  int getDroppedEventCount() => _prefs.getInt(_keyDroppedEventCount) ?? 0;

  Future<void> addDroppedEvents(int count) async {
    await _prefs.setInt(_keyDroppedEventCount, getDroppedEventCount() + count);
  }

  // ── Identity ───────────────────────────────────────────────────────────

  String? getUserId() => _prefs.getString(_keyUserId);

  Future<void> setUserId(String userId) async {
    await _prefs.setString(_keyUserId, userId);
  }

  Future<void> clearUserId() async {
    await _prefs.remove(_keyUserId);
  }

  /// An identify() call that could not reach the server yet.
  ///
  /// Persisted so a user who signs in offline is still identified when
  /// connectivity returns, rather than silently staying anonymous.
  String? getPendingIdentify() => _prefs.getString(_keyPendingIdentify);

  Future<void> setPendingIdentify(String payloadJson) async {
    await _prefs.setString(_keyPendingIdentify, payloadJson);
  }

  Future<void> clearPendingIdentify() async {
    await _prefs.remove(_keyPendingIdentify);
  }

  // ── Sessions ───────────────────────────────────────────────────────────

  String? getSessionId() => _prefs.getString(_keySessionId);

  Future<void> setSessionId(String sessionId) async {
    await _prefs.setString(_keySessionId, sessionId);
  }

  DateTime? getSessionLastActive() {
    final raw = _prefs.getString(_keySessionLastActive);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setSessionLastActive(DateTime time) async {
    await _prefs.setString(_keySessionLastActive, time.toIso8601String());
  }

  /// Clear all SmartLink data
  Future<void> clearAll() async {
    await _prefs.remove(_keyFirstLaunch);
    await _prefs.remove(_keyDeviceId);
    await _prefs.remove(_keyLastDeferredLinkCheck);
    await _prefs.remove(_keyLastDeferredLink);
    await _prefs.remove(_keyLastDeepLink);
    await _prefs.remove(_keyEventQueue);
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keySessionId);
    await _prefs.remove(_keySessionLastActive);
    await _prefs.remove(_keyPendingIdentify);
    await _prefs.remove(_keyDroppedEventCount);
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
