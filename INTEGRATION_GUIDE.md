# AE-LINK Integration Guide for AllEvents Flutter App

This guide provides step-by-step instructions for integrating the AE-LINK deferred deep linking SDK into the AllEvents Flutter application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Deep Link Setup](#deep-link-setup)
5. [Integration Steps](#integration-steps)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

- Flutter SDK (version 3.10.0 or higher)
- Android 5.0+ (API level 21) or iOS 12.0+
- Xcode (for iOS development)
- Android Studio (for Android development)
- AllEvents backend API credentials
- AE-LINK platform credentials

## Installation

### Step 1: Add the SDK to Your Project

1. Copy the AE-LINK SDK to your project:

```bash
cp -r flutter_sdk your_allevents_project/packages/ae_link
```

Or clone it as a git submodule:

```bash
git submodule add https://github.com/allevents/flutter-sdk.git packages/ae_link
```

### Step 2: Update pubspec.yaml

Add the SDK as a local dependency:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ae_link:
    path: packages/ae_link
```

### Step 3: Install Dependencies

```bash
flutter pub get
```

## Configuration

### Step 1: Get API Credentials

Contact your AE-LINK administrator to obtain:
- API Base URL (e.g., `https://allevents.in`)
- Tenant API Key (unique to your application)

### Step 2: Create a Configuration File

Create `lib/config/ae_link_config.dart`:

```dart
/// AE-LINK Configuration for AllEvents
class AeLinkConstants {
  /// API base URL for AE-LINK backend
  static const String apiBaseUrl = 'https://allevents.in';

  /// Tenant API key (obtained from AE-LINK dashboard)
  static const String apiKey = 'your-api-key-here';

  /// Log level: -1 = detailed debug, 0 = minimal debug, 1 = release (no logs)
  static const int logLevel = 0; // Use 1 in production, -1 for deep debugging

  /// Request timeout in seconds
  static const int requestTimeoutSeconds = 30;

  /// Whether to automatically handle incoming deep links
  static const bool autoHandleDeepLinks = true;
}
```

**Security Note**: For production, use environment variables or a secure configuration service instead of hardcoding API keys.

## Deep Link Setup

### Android Configuration

#### Step 1: Update AndroidManifest.xml

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.allevents.app">

    <application
        android:label="AllEvents"
        android:icon="@mipmap/ic_launcher"
        android:debuggable="true">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <!-- Launcher intent filter -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <!-- Deep link intent filter for allevents:// scheme -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />

                <data
                    android:scheme="allevents"
                    android:host="event" />
            </intent-filter>

            <!-- Deep link intent filter for HTTPS (Universal Links) -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />

                <data
                    android:scheme="https"
                    android:host="allevents.in"
                    android:pathPrefix="/event" />
            </intent-filter>
        </activity>

        <!-- Flutter NativeView -->
        <activity
            android:name="io.flutter.embedding.android.FlutterActivity"
            android:exported="false" />
    </application>

    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

</manifest>
```

#### Step 2: Update build.gradle (Optional)

Ensure your app's `android/app/build.gradle` has the correct compileSdkVersion:

```gradle
android {
    compileSdkVersion 34

    defaultConfig {
        applicationId "com.allevents.app"
        minSdkVersion 21
        targetSdkVersion 34
        // ... rest of config
    }
}
```

### iOS Configuration

#### Step 1: Update Info.plist

Edit `ios/Runner/Info.plist` and add URL scheme:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ... existing config ... -->

    <!-- URL scheme for allevents:// links -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.allevents.app</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>allevents</string>
            </array>
        </dict>
    </array>

    <!-- Associated domains for Universal Links -->
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:allevents.in</string>
    </array>

    <!-- ... rest of config ... -->
</dict>
</plist>
```

#### Step 2: Enable Associated Domains

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability**
5. Search for and add **Associated Domains**
6. Add domain: `applinks:allevents.in`

#### Step 3: Upload apple-app-site-association

Ensure your backend hosts this file at `https://allevents.in/.well-known/apple-app-site-association`:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.allevents.app",
        "paths": ["/event", "/deeplink", "/ticket/*"]
      }
    ]
  }
}
```

Replace `TEAM_ID` with your Apple Team ID.

## Integration Steps

### Step 1: Initialize AE-LINK SDK in main()

Edit `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:ae_link/ae_link.dart';
import 'config/ae_link_config.dart';
import 'screens/home_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AE-LINK SDK
  try {
    await AeLinkSdk.initialize(
      AeLinkConfig(
        apiBaseUrl: AeLinkConstants.apiBaseUrl,
        tenantApiKey: AeLinkConstants.apiKey,
        logLevel: AeLinkConstants.logLevel,
        requestTimeoutSeconds: AeLinkConstants.requestTimeoutSeconds,
        autoHandleDeepLinks: AeLinkConstants.autoHandleDeepLinks,
      ),
    );
    print('AE-LINK SDK initialized successfully');
  } catch (e) {
    print('Failed to initialize AE-LINK SDK: $e');
  }

  // Check for deferred deep link on first app launch
  try {
    final deferredLink = await AeLinkSdk.checkDeferredLink();
    if (deferredLink != null) {
      print('Deferred link found: ${deferredLink.eventId}');
      // The deep link will be handled by the app's navigation
    }
  } catch (e) {
    print('Error checking deferred link: $e');
  }

  runApp(const AllEventsApp());
}
```

### Step 2: Create Deep Link Handler Service

Create `lib/services/deep_link_service.dart`:

```dart
import 'package:ae_link/ae_link.dart';
import 'package:flutter/material.dart';

/// Service for handling deep links in the AllEvents app
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();

  factory DeepLinkService() {
    return _instance;
  }

  DeepLinkService._internal();

  /// Navigate based on deep link data
  Future<void> handleDeepLink(
    DeepLinkData deepLinkData,
    NavigatorState navigatorState,
  ) async {
    try {
      // Log the deep link
      print('Handling deep link:');
      print('  Event ID: ${deepLinkData.eventId}');
      print('  Action: ${deepLinkData.action}');
      print('  Is Deferred: ${deepLinkData.isDeferred}');

      // Handle different actions
      switch (deepLinkData.action) {
        case 'view_event':
          _navigateToEventDetails(
            navigatorState,
            deepLinkData.eventId,
            deepLinkData,
          );
          break;

        case 'view_ticket':
          _navigateToTicketDetails(
            navigatorState,
            deepLinkData.eventId,
            deepLinkData,
          );
          break;

        case 'buy_ticket':
          _navigateToBuyTicket(
            navigatorState,
            deepLinkData.eventId,
            deepLinkData,
          );
          break;

        default:
          _navigateToEventDetails(
            navigatorState,
            deepLinkData.eventId,
            deepLinkData,
          );
      }

      // Confirm deferred link was shown
      if (deepLinkData.isDeferred && deepLinkData.deferredLinkId != null) {
        await AeLinkSdk.confirmDeepLink(deepLinkData.deferredLinkId!);
        print('Deferred link confirmed: ${deepLinkData.deferredLinkId}');
      }
    } catch (e) {
      print('Error handling deep link: $e');
    }
  }

  void _navigateToEventDetails(
    NavigatorState navigatorState,
    String? eventId,
    DeepLinkData deepLinkData,
  ) {
    if (eventId == null) return;

    // TODO: Replace with your actual event details route
    navigatorState.pushNamed(
      '/event/$eventId',
      arguments: {
        'deepLinkData': deepLinkData,
        'utmSource': deepLinkData.utmParams['utm_source'],
        'utmCampaign': deepLinkData.utmParams['utm_campaign'],
        'coupon': deepLinkData.couponCode,
      },
    );
  }

  void _navigateToTicketDetails(
    NavigatorState navigatorState,
    String? eventId,
    DeepLinkData deepLinkData,
  ) {
    if (eventId == null) return;

    navigatorState.pushNamed(
      '/event/$eventId/tickets',
      arguments: deepLinkData,
    );
  }

  void _navigateToBuyTicket(
    NavigatorState navigatorState,
    String? eventId,
    DeepLinkData deepLinkData,
  ) {
    if (eventId == null) return;

    navigatorState.pushNamed(
      '/event/$eventId/buy',
      arguments: {
        'deepLinkData': deepLinkData,
        'coupon': deepLinkData.couponCode,
      },
    );
  }
}
```

### Step 3: Add Deep Link Listener to Your App

Edit `lib/main.dart` and update the `AllEventsApp` widget:

```dart
class AllEventsApp extends StatefulWidget {
  const AllEventsApp({Key? key}) : super(key: key);

  @override
  State<AllEventsApp> createState() => _AllEventsAppState();
}

class _AllEventsAppState extends State<AllEventsApp> {
  late DeepLinkService _deepLinkService;

  @override
  void initState() {
    super.initState();
    _deepLinkService = DeepLinkService();
    _setupDeepLinkListener();
  }

  void _setupDeepLinkListener() {
    // Listen for deep links from AE-LINK SDK
    AeLinkSdk.onDeepLink.listen((deepLinkData) {
      // Use navigatorObservers to get the current navigator state
      // Or use a GlobalKey<NavigatorState>
      _deepLinkService.handleDeepLink(
        deepLinkData,
        Navigator.of(context),
      );
    }, onError: (error) {
      print('Error in deep link listener: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AllEvents',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      // Configure your routes here
      // ...
    );
  }

  @override
  void dispose() {
    // Clean up resources when app closes
    AeLinkSdk.dispose();
    super.dispose();
  }
}
```

### Step 4: Alternative: Use GlobalKey for Navigation

If you need more control over navigation, use a `GlobalKey<NavigatorState>`:

```dart
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AeLinkSdk.initialize(config);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: const HomeScreen(),
    );
  }
}

// Later, when handling deep links:
AeLinkSdk.onDeepLink.listen((deepLinkData) {
  _deepLinkService.handleDeepLink(
    deepLinkData,
    navigatorKey.currentState!,
  );
});
```

### Step 5: Track Deep Link Analytics (Optional)

Add analytics tracking for deep links:

```dart
void _setupDeepLinkListener() {
  AeLinkSdk.onDeepLink.listen((deepLinkData) {
    // Track analytics
    _analyticsService.logDeepLinkReceived(
      eventId: deepLinkData.eventId,
      action: deepLinkData.action,
      isDeferred: deepLinkData.isDeferred,
      source: deepLinkData.utmParams['utm_source'],
      campaign: deepLinkData.utmParams['utm_campaign'],
    );

    // Handle the deep link
    _deepLinkService.handleDeepLink(deepLinkData, navigatorKey.currentState!);
  });
}
```

## Testing

### Manual Deep Link Testing

#### Android

Test with custom scheme:

```bash
# Open event details
adb shell am start -a android.intent.action.VIEW \
  -d "allevents://event?event_id=12345&action=view_event&utm_source=test"

# Open ticket purchase
adb shell am start -a android.intent.action.VIEW \
  -d "allevents://event?event_id=12345&action=buy_ticket&coupon_code=SAVE20"
```

Test with https scheme (requires App Links verification):

```bash
adb shell am start -a android.intent.action.VIEW \
  -d "https://allevents.in/event/12345?utm_source=email&utm_campaign=launch"
```

#### iOS

Using xcrun:

```bash
# Open event details
xcrun simctl openurl booted \
  "allevents://event?event_id=12345&action=view_event&utm_source=test"

# Open ticket purchase
xcrun simctl openurl booted \
  "allevents://event?event_id=12345&action=buy_ticket&coupon_code=SAVE20"
```

Or use Safari to test Universal Links (on real device or configured simulator).

### Testing Deferred Links

1. **First Launch**: The SDK automatically checks for deferred links on first app launch.
2. **Force Check**: Use `AeLinkSdk.forceCheckDeferredLink()` to manually trigger a check:

```dart
final deferredLink = await AeLinkSdk.forceCheckDeferredLink();
if (deferredLink != null) {
  print('Found deferred link: ${deferredLink.eventId}');
}
```

3. **Test in Example App**: Run the provided example app to test the SDK independently.

### Debug Logging

Use the `logLevel` parameter to control SDK output:

```dart
AeLinkConfig(
  apiBaseUrl: 'https://allevents.in',
  tenantApiKey: 'your-key',
  logLevel: 0,  // -1 = detailed debug, 0 = minimal debug, 1 = release (no logs)
)
```

**logLevel: 0** — Info, warnings, and errors. Good for development.

**logLevel: -1** — Everything above plus structured verbose output:
- Device fingerprint data (screen, locale, timezone, etc.)
- HTTP requests and responses with status codes
- Operation timing (e.g., fingerprint collection duration)

**logLevel: 1** — Silent. Use in production.

**Backward compatible:** `debug: true` still works and maps to `logLevel: 0`.

## Troubleshooting

### Issue: Deep links not being received

**Possible Causes & Solutions:**

1. **Deep link scheme not configured**
   - Verify AndroidManifest.xml has correct intent filters
   - Verify Info.plist has correct CFBundleURLSchemes
   - Rebuild the app: `flutter clean && flutter pub get`

2. **SDK not initialized**
   - Ensure `AeLinkSdk.initialize()` is called in `main()`
   - Check logs for initialization errors

3. **Deep link not being processed**
   - Ensure listener is set up: `AeLinkSdk.onDeepLink.listen(...)`
   - Check that handler doesn't throw exceptions

**Debug:**
```dart
// Verify SDK is initialized
print('SDK initialized: ${AeLinkSdk.isInitialized}');

// Manually test a deep link
AeLinkSdk.processDeepLink('allevents://event?event_id=123');

// Check last deep link
print('Last deep link: ${AeLinkSdk.lastDeepLink}');
```

### Issue: Deferred links not matching

**Possible Causes & Solutions:**

1. **Network connectivity issue**
   - Ensure device has internet connection
   - Check API base URL is correct
   - Verify API key is valid

2. **First launch not detected**
   - Deferred link checking only happens on first launch
   - Use `forceCheckDeferredLink()` to test
   - Clear app data to simulate first launch

3. **Backend not returning matches**
   - Verify deep links are configured on AE-LINK backend
   - Check that device fingerprint matches stored data
   - Review backend logs for API errors

**Debug:**
```dart
// Check device ID
print('Device ID: ${AeLinkSdk.getDeviceId()}');

// Force check and log result
final link = await AeLinkSdk.forceCheckDeferredLink();
print('Force check result: $link');
```

### Issue: App crashes after deep link

**Possible Causes & Solutions:**

1. **Null navigation context**
   - Ensure navigator is available when handling deep links
   - Use GlobalKey<NavigatorState> for safer access

2. **Invalid event ID**
   - Validate event ID before navigation
   - Handle missing data gracefully

3. **Route not registered**
   - Verify deep link routes are registered in your app
   - Add error handling for unknown routes

**Fix:**
```dart
void _navigateToEvent(NavigatorState? navigator, String? eventId) {
  if (navigator == null || eventId == null) {
    print('Cannot navigate: missing navigator or event ID');
    return;
  }

  try {
    navigator.pushNamed('/event/$eventId');
  } catch (e) {
    print('Navigation error: $e');
  }
}
```

### Issue: Permissions errors

**Possible Causes & Solutions:**

1. **Missing AndroidManifest.xml permissions**
   - Add INTERNET and ACCESS_NETWORK_STATE permissions
   - See Android Configuration section

2. **iOS entitlements missing**
   - Ensure Associated Domains capability is enabled
   - Update apple-app-site-association file

**Debug:**
Set `logLevel: -1` to see detailed logs including HTTP errors and fingerprint data.

### Performance Issues

If deep link handling is causing app slowdowns:

1. Set `autoHandleDeepLinks: false` if you don't need immediate handling
2. Use `logLevel: 1` in production (no logs)
3. Increase `requestTimeoutSeconds` if network is slow

```dart
AeLinkConfig(
  apiBaseUrl: 'https://allevents.in',
  tenantApiKey: 'your-key',
  logLevel: 1,  // Silent in production
  requestTimeoutSeconds: 45,
  autoHandleDeepLinks: true,
)
```

## Next Steps

1. **Customize Deep Link Handling**: Update `DeepLinkService` to match your app's navigation
2. **Add Analytics**: Track deep link conversions and user behavior
3. **Test Thoroughly**: Test all deep link scenarios in development and staging
4. **Deploy**: Update AndroidManifest.xml and apple-app-site-association in production
5. **Monitor**: Check logs regularly for errors or unexpected behavior

## Support Resources

- **SDK Documentation**: See README.md in the SDK root
- **Example App**: Review `example/main.dart` for implementation reference
- **API Logs**: Enable debug logging to troubleshoot issues
- **Backend Dashboard**: Check AE-LINK dashboard for link configuration and analytics

## Checklist

Before deploying to production:

- [ ] AE-LINK SDK initialized in `main()`
- [ ] Deep link listener configured
- [ ] Deep link routes implemented
- [ ] AndroidManifest.xml has correct intent filters
- [ ] iOS Info.plist has correct URL schemes
- [ ] iOS Associated Domains configured
- [ ] apple-app-site-association file uploaded to backend
- [ ] API base URL and API key configured correctly
- [ ] Log level set to release (`logLevel: 1`)
- [ ] Deep links tested on both iOS and Android
- [ ] Deferred links tested in staging environment
- [ ] Analytics integration added
- [ ] Error handling implemented
