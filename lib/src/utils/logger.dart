import 'package:logger/logger.dart';

/// Logger for AE-LINK SDK — simple one-line output
class AeLinkLogger {
  static final Logger _logger = Logger(
    printer: SimplePrinter(
      colors: true,
      printTime: false,
    ),
  );

  static late bool _isDebug;

  /// Initialize the logger with debug setting
  static void init({required bool debug}) {
    _isDebug = debug;
  }

  /// Log a debug message
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.d('[AE-LINK] $message', error: error, stackTrace: stackTrace);
    }
  }

  /// Log an info message
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.i('[AE-LINK] $message', error: error, stackTrace: stackTrace);
    }
  }

  /// Log a warning message
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w('[AE-LINK] $message', error: error, stackTrace: stackTrace);
  }

  /// Log an error message
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e('[AE-LINK] $message', error: error, stackTrace: stackTrace);
  }

  /// Log an error in a try-catch
  static void errorWithStackTrace(
    String message,
    dynamic error,
    StackTrace stackTrace,
  ) {
    _logger.e('[AE-LINK] $message', error: error, stackTrace: stackTrace);
  }
}
