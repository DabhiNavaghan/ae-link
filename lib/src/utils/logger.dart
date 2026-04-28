/// Log level for SmartLink SDK
///
/// -1 = verbose (extra detail for deep debugging)
///  0 = minimal debug (actions + results only)
///  1 = release / silent (no logs)
class SmartLinkLogger {
  static int _logLevel = 1;
  static const String _tag = 'SmartLink';

  /// Initialize with log level
  static void init({int logLevel = 1}) {
    _logLevel = logLevel;
  }

  /// Backward-compatible init from bool
  static void initFromDebug({required bool debug}) {
    _logLevel = debug ? 0 : 1;
  }

  /// Current log level
  static int get logLevel => _logLevel;

  // ── Level 0: minimal debug (key events) ──

  /// Log info — visible at level 0 and -1
  static void info(String message) {
    if (_logLevel > 0) return;
    _print('INFO', message);
  }

  /// Log warning — visible at level 0 and -1
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_logLevel > 0) return;
    _print('WARN', message);
    if (error != null) _print('WARN', '  ↳ $error');
    if (stackTrace != null && _logLevel < 0) _print('WARN', '$stackTrace');
  }

  /// Log error — visible at level 0 and -1
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_logLevel > 0) return;
    _print('ERR', message);
    if (error != null) _print('ERR', '  ↳ $error');
    if (stackTrace != null && _logLevel < 0) _print('ERR', '$stackTrace');
  }

  /// Log error with stack trace — visible at level 0 and -1
  static void errorWithStackTrace(String message, dynamic error, StackTrace stackTrace) {
    if (_logLevel > 0) return;
    _print('ERR', message);
    _print('ERR', '  ↳ $error');
    if (_logLevel < 0) _print('ERR', '$stackTrace');
  }

  // ── Level 0: basic debug ──

  /// Log debug — visible at level 0 and -1
  static void debug(String message) {
    if (_logLevel > 0) return;
    _print('DBG', message);
  }

  // ── Level -1: verbose ──

  /// Log verbose detail — only visible at level -1
  static void verbose(String message) {
    if (_logLevel >= 0) return;
    _print('VRB', message);
  }

  // ── Internal ──

  static void _print(String level, String message) {
    // ignore: avoid_print
    print('[$_tag] $level  $message');
  }
}
