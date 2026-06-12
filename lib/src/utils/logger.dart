import 'package:flutter/foundation.dart';

/// Log level for SmartLink SDK
///
/// -1 = verbose (extra detail for deep debugging)
///  0 = minimal debug (actions + results only)
///  1 = release / silent (no logs)
///
/// NOTE: All logs are completely suppressed in release builds
/// regardless of logLevel. Zero print() calls in production.
class SmartLinkLogger {
  static int _logLevel = 1;
  static const String _tag = 'SmartLink';

  /// Initialize with log level
  static void init({int logLevel = 1}) {
    _logLevel = logLevel;
  }

  /// Current log level
  static int get logLevel => _logLevel;

  // ── Level 0: minimal debug (key events) ──

  static void info(String message) {
    if (kReleaseMode || _logLevel > 0) return;
    _print('INFO', message);
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kReleaseMode || _logLevel > 0) return;
    _print('WARN', message);
    if (error != null) _print('WARN', '  ↳ $error');
    if (stackTrace != null && _logLevel < 0) _print('WARN', '$stackTrace');
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kReleaseMode || _logLevel > 0) return;
    _print('ERR', message);
    if (error != null) _print('ERR', '  ↳ $error');
    if (stackTrace != null && _logLevel < 0) _print('ERR', '$stackTrace');
  }

  static void errorWithStackTrace(String message, dynamic error, StackTrace stackTrace) {
    if (kReleaseMode || _logLevel > 0) return;
    _print('ERR', message);
    _print('ERR', '  ↳ $error');
    if (_logLevel < 0) _print('ERR', '$stackTrace');
  }

  // ── Level 0: basic debug ──

  static void debug(String message) {
    if (kReleaseMode || _logLevel > 0) return;
    _print('DBG', message);
  }

  // ── Level -1: verbose ──

  static void verbose(String message) {
    if (kReleaseMode || _logLevel >= 0) return;
    _print('VRB', message);
  }

  static void data(String label, Map<String, dynamic> fields) {
    if (kReleaseMode || _logLevel >= 0) return;
    final entries = fields.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}: ${e.value}')
        .join(' | ');
    _print('DATA', '$label → $entries');
  }

  // ── Internal ──

  static void _print(String level, String message) {
    // ignore: avoid_print
    print('[$_tag] $level  $message');
  }
}
