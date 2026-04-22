# Changelog

All notable changes to the AE-LINK Flutter SDK will be documented in this file.

## [1.0.0] - 2026-04-07

### Added
- Initial release of AE-LINK Flutter SDK
- Device fingerprinting capabilities with automatic collection of:
  - Device model, manufacturer, OS version
  - Screen dimensions and density
  - Device locale and timezone
  - Network connection type
  - App version and build number
  - Unique device ID
- Deferred deep link matching via device fingerprint
- Support for direct deep links via app_links package
- Unified stream for both deferred and direct deep links
- Local storage with SharedPreferences for:
  - First launch detection
  - Device ID persistence
  - Last deferred link check timestamp
  - Last deep link data caching
- Comprehensive error handling and logging
- Full null safety support
- Production-ready code with proper exception handling
- Example integration app
- Detailed README and integration guide
- Support for both iOS (Universal Links) and Android (App Links)
- Deep link confirmation tracking for deferred links

### Features
- **AeLinkSdk singleton class** for easy access
- **AeLinkConfig** for flexible configuration
- **DeepLinkData** model for consistent deep link handling
- **DeviceFingerprint** model for device information
- **LinkParams** model for UTM and parameter handling
- **FingerprintService** for automated device fingerprint collection
- **DeferredLinkService** for API communication with AE-LINK backend
- **DeepLinkHandler** for listening to incoming deep links
- **StorageService** for persistent local storage
- **AeLinkLogger** for debugging and monitoring

### Dependencies
- http: ^1.1.0
- shared_preferences: ^2.2.2
- device_info_plus: ^9.1.1
- package_info_plus: ^4.2.0
- app_links: ^3.4.5
- connectivity_plus: ^5.1.0
- uuid: ^4.0.0
- logger: ^2.0.2+1
