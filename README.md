# SmartLink Flutter SDK

Flutter SDK for deep linking with the SmartLink platform. Handles two separate scenarios with separate callbacks:

1. **Direct Deep Link** (`onDeepLink`) → App is installed, user clicks a link, app opens with link data
2. **Deferred Deep Link** (`onDeferredDeepLink`) → App is NOT installed, user clicks link → store → installs → first launch delivers the original link data

**Backend:** [smartlink-backend](https://github.com/DabhiNavaghan/ae-link-backend)
**SDK Repo:** [smartlink](https://github.com/DabhiNavaghan/ae-link)
**Dashboard:** [smartlink-coral.vercel.app](https://smartlink-coral.vercel.app)

## Setup

### 1. Add dependency

```yaml
# pubspec.yaml
dependencies:
  smartlink:
    git:
      url: https://github.com/DabhiNavaghan/ae-link.git
```

### 2. Register your app in the dashboard

Go to your dashboard and add your app with:

**Android:**
- Package name: `com.yourcompany.yourapp`
- SHA-256 fingerprint: (get it with `./gradlew signingReport`)
- Play Store URL

**iOS:**
- Bundle ID: `com.yourcompany.yourapp`
- Team ID: (from [developer.apple.com/account](https://developer.apple.com/account) → Membership)
- App Store URL

### 3. Android — App Links setup

Add to `android/app/src/main/AndroidManifest.xml` inside your `<activity>` tag:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop">

    <!-- Existing launcher intent filter -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>

    <!-- SmartLink App Links -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="smartlink-coral.vercel.app" />
    </intent-filter>
</activity>
```

Replace the host with your deployment domain if different.

### 4. iOS — Universal Links setup

In Xcode, go to your target → Signing & Capabilities → add "Associated Domains" and add:

```
applinks:smartlink-coral.vercel.app
```

### 5. Initialize the SDK

Create `lib/services/smart_link_service.dart`:

```dart
import 'package:smartlink/smartlink.dart';
import 'package:flutter/widgets.dart';

late SmartLink smartLink;

Future<DeepLinkData?> initSmartLink({bool isExistingUser = false}) async {
  smartLink = SmartLink(
    apiKey: 'YOUR_API_KEY',       // From dashboard Settings
    apiBaseUrl: 'https://smartlink-coral.vercel.app',
    logLevel: 0,                   // -1 = detailed debug, 0 = minimal debug, 1 = release (no logs)
    isExistingUser: isExistingUser,

    // Called when app is ALREADY installed and user clicks a link
    onDeepLink: (data) {
      print('Direct deep link: ${data.destinationUrl}');
      // Navigate to the content
    },

    // Called on FIRST LAUNCH if user installed via a link
    onDeferredDeepLink: (data) {
      print('Deferred deep link: ${data.destinationUrl}');
      // Navigate to the content they originally clicked
    },
  );

  return await smartLink.initialize();
}
```

Then in `main.dart`:

```dart
import 'services/smart_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initSmartLink(isExistingUser: false);

  runApp(MyApp());
}
```

## Two Callbacks — When Each Fires

### `onDeepLink` — Direct Deep Link
- App is **already installed** on the device
- User clicks a SmartLink URL (e.g., `https://smartlink-coral.vercel.app/xGJEQJR`)
- Android/iOS opens the app directly via App Links / Universal Links
- `onDeepLink` fires with the link data

### `onDeferredDeepLink` — Deferred Deep Link
- App is **NOT installed** on the device
- User clicks a SmartLink URL in their browser
- Browser collects a device fingerprint and redirects to the app store
- User installs the app from the store
- On **first launch**, the SDK matches the device fingerprint
- `onDeferredDeepLink` fires with the original link data

These callbacks **never overlap** — a deep link is either direct or deferred, never both.

## Available data in DeepLinkData

```dart
// Both callbacks receive the same DeepLinkData object:
data.linkId;           // Original link ID
data.destinationUrl;   // "https://allevents.in/event/..."
data.eventId;          // "12345"
data.action;           // "view_event", "buy_ticket"
data.isDeferred;       // true = deferred, false = direct
data.deferredLinkId;   // Only set for deferred links

// Campaign data
data.campaignId;       // Campaign ID
data.campaignName;     // "summer-promo"
data.campaign;         // Full campaign object with metadata

// UTM params
data.linkParams?.utmSource;    // "email"
data.linkParams?.utmMedium;    // "newsletter"
data.linkParams?.utmCampaign;  // "summer-promo"

// Special params
data.linkParams?.couponCode;   // "SAVE20"
data.linkParams?.referralCode; // "REF123"
data.linkParams?.userEmail;    // "user@example.com"
```

## Log Levels

The SDK uses an integer-based log level system:

| Level | Name | Use For |
|-------|------|---------|
| `-1` | Detailed debug | Structured verbose logs — fingerprint data, HTTP requests/responses, timing |
| `0` | Minimal debug | Info, warnings, errors — good for development |
| `1` | Release | Silent — no logs (default) |

**logLevel: 0 (minimal debug) — development:**
```
[SmartLink] INF  Initializing SmartLink SDK...
[SmartLink] INF  Launch: first_install
[SmartLink] INF  SDK ready
[SmartLink] INF  First launch — checking deferred link...
[SmartLink] INF  ✅ DEFERRED LINK MATCHED! Score: 100
[SmartLink] INF  Deferred link matched: abc123
```

**logLevel: -1 (detailed debug) — deep debugging:**
```
[SmartLink] VRB  Collecting full device info...
[SmartLink] DAT  ┌ fingerprint
               │ screenWidth: 1080.0
               │ screenHeight: 2400.0
               │ locale: en-US
               │ timezone: +05:30
               └
[SmartLink] HTTP GET https://smartlink-coral.vercel.app/api/v1/deferred/match → 200
[SmartLink] TIME fingerprint_collection: 42ms
[SmartLink] INF  ✅ DEFERRED LINK MATCHED! Score: 100
```

**logLevel: 1 (release) — production:**
No output.

**Backward compatibility:** `debug: true` still works and maps to `logLevel: 0`.

## Troubleshooting

**"App doesn't open when I click the link"**
- Make sure you registered the app in the dashboard with the correct package name and SHA-256
- Verify `assetlinks.json` is served: visit `https://your-domain/.well-known/assetlinks.json`
- On Android: run `adb shell pm get-app-links com.yourpackage`
- On iOS: check Associated Domains is enabled in Xcode

**"Deferred link not matching"**
- Uninstall the app completely before testing (SharedPreferences must be cleared)
- Click the link in a browser first, then install the app within 6 hours
- Set `logLevel: -1` to see detailed matching logs, fingerprint data, and scores
- The match requires 60+ points (screen + timezone + language + proximity = 60 without IP)

**"onDeepLink fires but onDeferredDeepLink doesn't (or vice versa)"**
- They are separate callbacks — only one fires per scenario
- `onDeepLink` = app was already installed when link was clicked
- `onDeferredDeepLink` = app was installed AFTER clicking the link

## License

See LICENSE file.
