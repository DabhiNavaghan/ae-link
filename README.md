# AE-LINK Flutter SDK

Flutter SDK for deferred deep linking with the AE-LINK platform. Collects device fingerprints, matches them against stored browser fingerprints, and delivers the original link context into the app after installation.

**Backend:** [ae-link-backend](https://github.com/DabhiNavaghan/ae-link-backend)
**SDK Repo:** [ae-link](https://github.com/DabhiNavaghan/ae-link)

## How It Works

1. User clicks a short link (e.g., `aelink.vercel.app/TG5hid0`) in a browser
2. The redirect page collects a browser fingerprint and redirects to the app store
3. User installs the app and opens it
4. The SDK collects a device fingerprint and calls the backend to find a match
5. If matched, the SDK returns the original link data (event ID, params, UTMs, etc.)
6. Your app navigates the user to the right screen

The matching uses IP address (40pts), screen resolution (20pts), timezone (15pts), language (10pts), and time proximity (15pts) — no cookies or advertising IDs required.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ae_link:
    git:
      url: https://github.com/DabhiNavaghan/ae-link.git
```

### Platform Setup

#### Android — `AndroidManifest.xml`

Add intent filters for App Links:

```xml
<activity android:name=".MainActivity" android:exported="true">
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="aelink.vercel.app" />
    </intent-filter>
</activity>
```

#### iOS — Associated Domains

In Xcode, add the Associated Domains capability:

```
applinks:aelink.vercel.app
```

Replace `aelink.vercel.app` with your actual deployment domain.

## Quick Start

### Initialize

```dart
import 'package:ae_link/ae_link.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AeLinkSdk.initialize(
    AeLinkConfig(
      apiBaseUrl: 'https://aelink.vercel.app',  // Your backend URL
      tenantApiKey: 'your-api-key-here',
      debug: true,  // false in production
    ),
  );

  // Check for deferred deep link on first launch
  final deferredLink = await AeLinkSdk.checkDeferredLink();
  if (deferredLink != null) {
    // User installed the app from a link — navigate to the right screen
    handleDeepLink(deferredLink);
  }

  runApp(const MyApp());
}
```

### Listen for Deep Links

```dart
@override
void initState() {
  super.initState();

  // Stream of all deep links (deferred + direct app links)
  AeLinkSdk.onDeepLink.listen((deepLink) {
    handleDeepLink(deepLink);
  });
}

void handleDeepLink(DeepLinkData data) {
  print('Event ID: ${data.eventId}');
  print('Action: ${data.action}');
  print('Is Deferred: ${data.isDeferred}');
  print('UTM Source: ${data.linkParams?.utmSource}');

  // Navigate based on action
  if (data.eventId != null) {
    Navigator.pushNamed(context, '/event/${data.eventId}');
  }

  // Confirm deferred link was shown (tracks conversion)
  if (data.isDeferred && data.deferredLinkId != null) {
    AeLinkSdk.confirmDeepLink(data.deferredLinkId!);
  }
}
```

## API Reference

### AeLinkSdk

```dart
// Initialize (required, call in main() before runApp)
static Future<void> initialize(AeLinkConfig config)

// Check for deferred link (call on first launch)
static Future<DeepLinkData?> checkDeferredLink()

// Force check (ignores first-launch check)
static Future<DeepLinkData?> forceCheckDeferredLink()

// Confirm deferred link was displayed
static Future<void> confirmDeepLink(String deferredLinkId)

// Process a deep link manually (e.g., from push notification)
static void processDeepLink(String url)

// Stream of all deep link events
static Stream<DeepLinkData> get onDeepLink

// Last received deep link
static DeepLinkData? get lastDeepLink

// Device ID for this device
static String? getDeviceId()

// Clear all cached SDK data
static Future<void> clearAll()

// Cleanup
static Future<void> dispose()
```

### AeLinkConfig

```dart
AeLinkConfig(
  apiBaseUrl: 'https://aelink.vercel.app',  // Required
  tenantApiKey: 'your-api-key',             // Required
  debug: false,                              // Enable debug logging
  requestTimeoutSeconds: 30,                 // API timeout
  autoHandleDeepLinks: true,                 // Auto-listen for app links
)
```

### DeepLinkData

```dart
class DeepLinkData {
  final String? linkId;
  final String? deferredLinkId;
  final String? eventId;
  final String? action;           // view_event, buy_ticket, etc.
  final String? destinationUrl;
  final LinkParams? linkParams;   // UTMs, coupon, referral, custom
  final bool isDeferred;
  final DateTime? clickedAt;
  final String? rawUrl;
}
```

### DeviceFingerprint

Collected automatically by the SDK. Matches browser fingerprint format:

| Field | Format | Browser Equivalent |
|-------|--------|--------------------|
| Screen width/height | Physical pixels (logical × density) | `window.screen.width/height` |
| Locale | `en-US` (hyphen separator) | `navigator.language` |
| Timezone | IANA name (e.g., `Asia/Kolkata`) | `Intl.DateTimeFormat().resolvedOptions().timeZone` |
| Timezone offset | `+05:30` format | `new Date().getTimezoneOffset()` |

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `http` | ^1.3.0 | HTTP client |
| `shared_preferences` | ^2.5.0 | Local storage |
| `device_info_plus` | ^11.0.0 | Device info |
| `package_info_plus` | ^8.0.0 | App version info |
| `app_links` | ^6.4.0 | Universal/App Links |
| `connectivity_plus` | ^6.1.0 | Network type |
| `uuid` | ^4.5.0 | Device ID generation |
| `logger` | ^2.5.0 | Debug logging |

## Troubleshooting

**Deep links not opening the app:** Verify your `AndroidManifest.xml` intent filters and iOS Associated Domains match your deployment domain. Test with `adb shell am start -a android.intent.action.VIEW -d "https://aelink.vercel.app/YOUR_SHORT_CODE"`.

**Deferred links not matching:** Enable `debug: true` and check logs. The match requires 60+ points. Most common issue: user changed networks between clicking and installing (different IP = -40 points). Check `matchScore` and `matchDetails` in the API response.

**SDK not initializing:** Ensure `WidgetsFlutterBinding.ensureInitialized()` is called before `AeLinkSdk.initialize()`.

## License

See LICENSE file.
