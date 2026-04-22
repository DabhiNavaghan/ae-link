# AE-LINK Flutter SDK

A comprehensive Flutter SDK for integrating deferred deep linking with the AE-LINK platform. The SDK automatically collects device fingerprints, matches them against stored deferred links, and provides a unified interface for handling both deferred and direct deep links.

## Features

- **Device Fingerprinting**: Automatic collection of device characteristics (model, OS, screen size, locale, timezone, etc.)
- **Deferred Deep Linking**: Match fingerprints against stored deep links to enable reliable deep linking even before app installation
- **Direct Deep Link Handling**: Support for traditional Universal Links (iOS) and App Links (Android)
- **Unified Deep Link Stream**: Single stream for both deferred and direct deep links
- **Local Storage**: Caches fingerprints and deep link data using SharedPreferences
- **Production Ready**: Full error handling, logging, and null safety

## Installation

### 1. Add to pubspec.yaml

```yaml
dependencies:
  ae_link:
    path: ../ae_link  # Adjust path as needed
```

### 2. Configure Deep Links for Your App

#### Android (app/build.gradle)

```gradle
android {
    defaultConfig {
        // ... other config
    }
}
```

#### AndroidManifest.xml

Add intent filters for your deep link scheme:

```xml
<manifest ...>
    <application ...>
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <!-- Your main intent filter -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <!-- Deep link intent filter -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />

                <!-- Replace with your domain -->
                <data
                    android:scheme="https"
                    android:host="allevents.in"
                    android:pathPrefix="/deeplink" />

                <!-- Also support custom scheme -->
                <data
                    android:scheme="allevents"
                    android:host="event" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

#### iOS (ios/Runner/Info.plist)

Add URL scheme:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.example.allevents</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>allevents</string>
        </array>
    </dict>
</array>
```

### 3. iOS Associated Domains

To support Universal Links, add to ios/Runner/Runner.entitlements:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:allevents.in</string>
</array>
```

And ensure your backend hosts an apple-app-site-association file at:
`https://allevents.in/.well-known/apple-app-site-association`

## Quick Start

### Initialize SDK

In your `main()` function:

```dart
import 'package:ae_link/ae_link.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SDK
  await AeLinkSdk.initialize(
    AeLinkConfig(
      apiBaseUrl: 'https://allevents.in',
      tenantApiKey: 'your-api-key-here',
      debug: true, // Set to false in production
    ),
  );

  runApp(const MyApp());
}
```

### Listen for Deep Links

```dart
void initState() {
  super.initState();

  // Listen for all deep links (deferred or direct)
  AeLinkSdk.onDeepLink.listen((deepLinkData) {
    handleDeepLink(deepLinkData);
  });
}

void handleDeepLink(DeepLinkData deepLinkData) {
  print('Event ID: ${deepLinkData.eventId}');
  print('Action: ${deepLinkData.action}');
  print('Is Deferred: ${deepLinkData.isDeferred}');

  // Navigate based on the action
  switch (deepLinkData.action) {
    case 'view_event':
      navigateToEventDetails(deepLinkData.eventId);
      break;
    case 'buy_ticket':
      navigateToBuyTicket(deepLinkData.eventId);
      break;
  }

  // Confirm deferred link was shown
  if (deepLinkData.isDeferred && deepLinkData.deferredLinkId != null) {
    AeLinkSdk.confirmDeepLink(deepLinkData.deferredLinkId!);
  }
}
```

### Check for Deferred Links on First Launch

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AeLinkSdk.initialize(config);

  // Check for deferred deep link on app first launch
  final deferredLink = await AeLinkSdk.checkDeferredLink();
  if (deferredLink != null) {
    // Handle the deferred link
    handleDeepLink(deferredLink);
  }

  runApp(const MyApp());
}
```

## API Reference

### AeLinkSdk

Main SDK class (singleton).

#### Methods

```dart
// Initialize the SDK (required before using other methods)
static Future<void> initialize(AeLinkConfig config)

// Check for deferred link on first app launch
static Future<DeepLinkData?> checkDeferredLink()

// Confirm that a deferred link was shown to the user
static Future<void> confirmDeepLink(String deferredLinkId)

// Manually process a deep link (for custom sources like push notifications)
static void processDeepLink(String url)

// Force check for deferred link (ignores time threshold)
static Future<DeepLinkData?> forceCheckDeferredLink()

// Get the device ID for this device
static String? getDeviceId()

// Clear all cached SDK data
static Future<void> clearAll()

// Dispose SDK and cleanup resources
static Future<void> dispose()
```

#### Properties

```dart
// Stream of deep link events (both deferred and direct)
static Stream<DeepLinkData> get onDeepLink

// Get the last received deep link
static DeepLinkData? get lastDeepLink

// Check if SDK has been initialized
static bool get isInitialized
```

### AeLinkConfig

Configuration class for the SDK.

```dart
AeLinkConfig(
  apiBaseUrl: 'https://allevents.in',        // Required: API base URL
  tenantApiKey: 'your-api-key',              // Required: API key
  debug: false,                              // Optional: Enable debug logging
  requestTimeoutSeconds: 30,                 // Optional: API timeout
  autoHandleDeepLinks: true,                 // Optional: Auto-listen for deep links
  customHeaders: {},                         // Optional: Custom HTTP headers
)
```

### DeepLinkData

Represents resolved deep link data.

```dart
class DeepLinkData {
  final String? linkId;                    // Unique identifier for this link
  final String? deferredLinkId;            // Deferred link ID (if from deferred matching)
  final String? eventId;                   // Event ID to navigate to
  final String? action;                    // Action: view_event, buy_ticket, etc.
  final String? destinationUrl;            // Destination URL if applicable
  final LinkParams? linkParams;            // UTM and other parameters
  final bool isDeferred;                   // true if from deferred matching
  final DateTime? clickedAt;               // When the link was clicked/matched
  final String? rawUrl;                    // Raw deep link URL

  // Convenience getters
  Map<String, String> get utmParams        // Get UTM params as map
  String? get userEmail
  String? get userId
  String? get couponCode
  String? get referralCode
  Map<String, dynamic>? get customParams
}
```

### LinkParams

Contains link parameters and UTM data.

```dart
class LinkParams {
  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? utmTerm;
  final String? utmContent;
  final String? userEmail;
  final String? userId;
  final String? couponCode;
  final String? referralCode;
  final Map<String, dynamic>? customParams;

  Map<String, String> getUtmParams()  // Get only UTM params
}
```

### DeviceFingerprint

Represents collected device data (used internally).

```dart
class DeviceFingerprint {
  final String? deviceId;
  final String? deviceModel;
  final String? deviceManufacturer;
  final String? osVersion;
  final String? osName;
  final double? screenWidth;
  final double? screenHeight;
  final double? screenDensity;
  final String? locale;
  final String? timezone;
  final String? connectionType;
  final String? appVersion;
  final String? appBuildNumber;
  final DateTime? collectedAt;
  // ... and more
}
```

## Deep Link URL Format

Deep links should follow this format:

```
allevents://event?event_id=12345&action=view_event&utm_source=email&utm_campaign=launch&coupon_code=SAVE20
```

Query parameters:

- `event_id` - Event ID (required for event actions)
- `action` - Action to perform: `view_event`, `view_ticket`, `buy_ticket`, etc.
- `utm_source` - UTM source parameter
- `utm_medium` - UTM medium parameter
- `utm_campaign` - UTM campaign parameter
- `utm_term` - UTM term parameter
- `utm_content` - UTM content parameter
- `user_email` - User email hint
- `user_id` - User ID hint
- `coupon_code` - Coupon code to apply
- `referral_code` - Referral code
- Any other custom parameters will be included in `customParams`

## Best Practices

1. **Initialize Early**: Call `AeLinkSdk.initialize()` in `main()` before `runApp()`.

2. **Check for Deferred Links**: Always call `AeLinkSdk.checkDeferredLink()` on first launch to detect pre-installation deep links.

3. **Handle All Deep Links Uniformly**: Use the `onDeepLink` stream to handle both deferred and direct deep links consistently.

4. **Confirm Deferred Links**: After displaying content from a deferred link, call `AeLinkSdk.confirmDeepLink()` to track the conversion.

5. **Error Handling**: The SDK handles errors gracefully and logs them. Check logs when troubleshooting.

6. **Disable Debug in Production**: Set `debug: false` in your `AeLinkConfig` for production builds.

7. **Test Deep Links**: Use the example app or manual URL schemes to test deep link handling.

## Troubleshooting

### Deep links not working

1. **Check AndroidManifest.xml**: Ensure intent filters are properly configured with the correct scheme/host.
2. **Check iOS Info.plist**: Verify URL types are configured.
3. **Test with URI**: Use `adb shell am start -a android.intent.action.VIEW -d "allevents://event?event_id=123"` on Android.
4. **Enable Debug Logging**: Set `debug: true` in `AeLinkConfig` to see detailed logs.

### Deferred links not matching

1. **API Configuration**: Verify `apiBaseUrl` and `tenantApiKey` are correct.
2. **Network Connectivity**: Check that the device has internet connectivity when `checkDeferredLink()` is called.
3. **Backend Status**: Ensure the AE-LINK backend is running and accessible.
4. **First Launch Only**: Deferred link checking only happens on first launch. Use `forceCheckDeferredLink()` to test.

### Fingerprint collection issues

1. **Permissions**: Ensure required permissions are granted (usually handled automatically).
2. **Device Info**: Some device info may not be available on emulators.
3. **Logs**: Check debug logs for which fields failed to collect.

## Example App

See `example/main.dart` for a complete working example with:
- SDK initialization
- Deep link listening
- Manual deep link testing
- Device ID display
- Force check functionality

## Dependencies

- `http` - HTTP client for API calls
- `shared_preferences` - Local storage
- `device_info_plus` - Device information
- `package_info_plus` - App package information
- `app_links` - Deep link handling
- `connectivity_plus` - Network connectivity
- `uuid` - UUID generation
- `logger` - Logging

## Support

For issues or questions:
1. Check the logs with `debug: true`
2. Review the example app
3. Consult the AE-LINK API documentation

## License

See LICENSE file in the SDK root directory.
