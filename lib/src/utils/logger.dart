import 'package:logger/logger.dart';

/// Logger for AE-LINK SDK
class AeLinkLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
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
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log an info message
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log a warning message
  static void warning(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log an error message
  static void error(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log an error in a try-catch
  static void errorWithStackTrace(
    String message,
    dynamic error,
    StackTrace stackTrace,
  ) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
