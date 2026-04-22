# AE-LINK Flutter SDK Architecture

## Overview

The AE-LINK Flutter SDK is a comprehensive deferred deep linking solution designed to enable reliable deep link matching even before app installation. The SDK follows clean architecture principles with clear separation of concerns.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    AeLinkSdk (Singleton)                    │
│  Main entry point managing SDK lifecycle and state           │
└─────────┬─────────────────────────────────────────────────┬─┘
          │                                                   │
    ┌─────▼──────────┐                           ┌──────────▼────┐
    │   Services     │                           │  Stream/Callbacks
    └────────────────┘                           └─────────────────┘
          │
    ┌─────┴─────────────────────────┬──────────────────┬──────────────┐
    │                               │                  │              │
┌───▼──────────┐    ┌──────────────▼────┐   ┌──────────▼──────┐   ┌──▼──────────────┐
│ Fingerprint  │    │  Deferred Link     │   │  Deep Link      │   │  Storage        │
│  Service     │    │  Service           │   │  Handler        │   │  Service        │
└──────────────┘    └────────────────────┘   └─────────────────┘   └─────────────────┘
        │                    │                        │                      │
        │                    │                        │                      │
    ┌───▼────┐          ┌────▼────┐           ┌──────▼────┐        ┌────────▼────┐
    │ Device │          │ HTTP    │           │  AppLinks │        │ Shared       │
    │ Info   │          │ Client  │           │  Package  │        │ Preferences  │
    │ Utils  │          │         │           │           │        │              │
    └────────┘          └─────────┘           └───────────┘        └──────────────┘
```

## Layer Architecture

### Presentation Layer (Application)
The app integrating the SDK interacts with:
- `AeLinkSdk` singleton
- `DeepLinkData` model for handling resolved links
- `Stream<DeepLinkData>` for reactive updates

### SDK Core Layer
**AeLinkSdk** (Main orchestrator)
- Manages SDK lifecycle (initialize, dispose)
- Coordinates services
- Exposes public API
- Manages stream broadcasting

### Service Layer
Handles specific responsibilities:

#### **FingerprintService**
- Collects device characteristics
- Creates fingerprint objects
- Manages device ID creation and storage

#### **DeferredLinkService**
- API communication with AE-LINK backend
- POST /api/v1/deferred/match for fingerprint matching
- POST /api/v1/deferred/confirm for conversion tracking
- Response parsing and error handling

#### **DeepLinkHandler**
- Listens for incoming app links via app_links package
- Parses URI to DeepLinkData
- Emits via stream for processing

#### **StorageService**
- Persistent data management
- First launch detection
- Device ID persistence
- Caching of deep link data
- Last check timestamp tracking

### Utility Layer
Helpers and utilities:

#### **DeviceInfoHelper**
- Gathers device information
- OS detection and version
- Screen dimensions
- Network connectivity
- App version
- Integrates with device_info_plus, package_info_plus

#### **AeLinkLogger**
- Structured logging
- Debug vs production modes
- Error tracking with stack traces

### Model Layer
Data classes:

#### **DeepLinkData**
- Unified representation of deep link (deferred or direct)
- Contains event ID, action, UTM params, etc.
- Serialization/deserialization support

#### **DeviceFingerprint**
- Device characteristics snapshot
- API representation
- JSON serialization for requests

#### **LinkParams**
- UTM parameters and link metadata
- User hints and coupons
- Custom parameters support

## Data Flow

### First Launch - Deferred Link Matching

```
1. App Launch
    ↓
2. AeLinkSdk.initialize()
    ↓
3. AeLinkSdk.checkDeferredLink()
    ↓
4. FingerprintService.collectFingerprint()
    ├─ DeviceInfoHelper.getDeviceModel()
    ├─ DeviceInfoHelper.getDeviceId()
    ├─ DeviceInfoHelper.getScreenDimensions()
    └─ ... collect all device info
    ↓
5. DeferredLinkService.matchFingerprint()
    ├─ POST /api/v1/deferred/match with fingerprint
    └─ Parse response
    ↓
6. If match found:
    ├─ StorageService.setLastDeferredLink()
    ├─ Emit via onDeepLink stream
    └─ Return DeepLinkData
    ↓
7. App handles DeepLinkData
    ├─ Navigate to event/ticket/etc
    └─ Call AeLinkSdk.confirmDeepLink()
    ↓
8. DeferredLinkService.confirmDeepLink()
    └─ POST /api/v1/deferred/confirm
```

### Direct Deep Link Handling

```
1. User clicks link or app opened with URI
    ↓
2. DeepLinkHandler receives URI via app_links
    ↓
3. Parse URI to DeepLinkData
    ├─ Extract event_id, action
    ├─ Parse UTM parameters
    └─ Create DeepLinkData.fromUrl()
    ↓
4. Emit via onDeepLink stream
    ↓
5. App listens and handles navigation
```

## Key Design Patterns

### Singleton Pattern
`AeLinkSdk` implements singleton to ensure single instance throughout app lifecycle.

```dart
static AeLinkSdk? _instance;
static AeLinkSdk get _sdkInstance {
  _instance ??= AeLinkSdk._internal();
  return _instance!;
}
```

### Service Locator Pattern
SDK provides static methods to access services without exposing implementation.

```dart
static Future<void> initialize(AeLinkConfig config)
static Stream<DeepLinkData> get onDeepLink
static Future<DeepLinkData?> checkDeferredLink()
```

### Repository Pattern
`StorageService` abstracts local storage implementation (could switch from SharedPreferences to other backends).

### Observer Pattern
`onDeepLink` stream uses broadcast stream for multiple subscribers.

```dart
final StreamController<DeepLinkData> _deepLinkStreamController =
    StreamController<DeepLinkData>.broadcast();
```

## Dependency Injection

Services are injected through constructors:

```dart
FingerprintService({required StorageService storageService})
    : _storageService = storageService;
```

## Error Handling Strategy

1. **Graceful Degradation**: Failed operations return null or false
2. **Logging**: All errors logged with stack traces in debug mode
3. **Timeouts**: Network requests have configurable timeouts
4. **Null Safety**: Full null safety with no runtime errors

Example:

```dart
try {
  final deferredLink = await matchFingerprint(fingerprint);
  return deferredLink;
} catch (e, stackTrace) {
  AeLinkLogger.errorWithStackTrace('Error matching fingerprint', e, stackTrace);
  return null; // Graceful degradation
}
```

## State Management

The SDK maintains minimal state:

- **Last Deep Link**: `DeepLinkData?` - cached for quick access
- **SDK Instance**: Singleton instance
- **Services**: Lazy-initialized on first use
- **Stream Controller**: Maintains subscription list

```dart
DeepLinkData? _lastDeepLink;
final StreamController<DeepLinkData> _deepLinkStreamController;
```

## Concurrency & Threading

- **Async Operations**: All I/O operations are async (storage, network)
- **Stream Events**: Emitted asynchronously via stream controller
- **No Blocking**: No synchronous blocking operations

```dart
final response = await _httpClient.post(url).timeout(Duration(...));
```

## Configuration & Flexibility

`AeLinkConfig` provides configuration for:

- API endpoint customization
- Debug mode toggle
- Timeout settings
- Custom headers
- Auto deep link handling toggle

## Testing Considerations

### Mockable Components
- `StorageService` uses SharedPreferences (can be mocked)
- `DeferredLinkService` uses http.Client (can be mocked)
- `DeepLinkHandler` uses app_links (can be mocked)

### Testable Design
- Pure functions for data transformation
- Dependency injection enables mocking
- Clear separation of concerns
- Minimal side effects

## Performance Optimizations

1. **Lazy Initialization**: Services initialized only when needed
2. **Caching**: Device ID and last deep link cached locally
3. **Timeouts**: Prevents hanging on network issues
4. **Efficient Serialization**: Direct JSON serialization without extra processing

## Security Considerations

1. **API Key**: Stored in config (should use environment variables in production)
2. **HTTPS**: API communication should be over HTTPS
3. **Local Storage**: Device ID stored in SharedPreferences (encrypted at OS level)
4. **Deep Link Validation**: URLs parsed and validated before use

## Extensibility Points

The SDK can be extended by:

1. **Custom Fingerprint Data**: `customData` field in DeviceFingerprint
2. **Custom Parameters**: `customParams` in LinkParams and DeepLinkData
3. **Custom Storage**: Replace StorageService implementation
4. **Custom HTTP Client**: Inject http.Client into DeferredLinkService
5. **Custom Logger**: Extend AeLinkLogger

## Dependencies

### Direct Dependencies
- `http` - HTTP client
- `shared_preferences` - Local storage
- `device_info_plus` - Device info
- `package_info_plus` - App info
- `app_links` - Deep link listening
- `connectivity_plus` - Network status
- `uuid` - ID generation
- `logger` - Logging

### Why Each Dependency
- **http**: Standard HTTP client for API calls
- **shared_preferences**: Simple, reliable local storage
- **device_info_plus**: Cross-platform device info
- **package_info_plus**: App version/build info
- **app_links**: Cross-platform deep link handling
- **connectivity_plus**: Network connectivity detection
- **uuid**: RFC 4122 compliant ID generation
- **logger**: Pretty-printed structured logging

## Version Strategy

- **Semantic Versioning**: MAJOR.MINOR.PATCH
- **Null Safety**: Requires Dart 3.0+
- **Flutter**: Targets Flutter 3.10.0+

## Future Enhancements

1. **Encryption**: Encrypted storage for sensitive data
2. **Analytics**: Built-in conversion tracking
3. **A/B Testing**: Support for A/B test variants
4. **Offline Support**: Queue requests when offline
5. **Custom Matchers**: Pluggable matching strategies
6. **Rate Limiting**: API rate limit handling
7. **Caching Headers**: HTTP cache control support

## Code Quality

- **Null Safety**: 100% null safe code
- **Linting**: Follows Dart style guide
- **Documentation**: Comprehensive inline documentation
- **Type Safety**: Strong typing throughout
- **Error Handling**: Explicit error handling, no silent failures

## Summary

The AE-LINK Flutter SDK provides a clean, maintainable, and extensible architecture for deferred deep linking. It separates concerns across multiple layers, uses proven design patterns, and provides a simple public API while maintaining flexibility for customization.
