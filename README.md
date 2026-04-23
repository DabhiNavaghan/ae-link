# AE-LINK Flutter SDK

Flutter SDK for deferred deep linking with the AE-LINK platform. Handles two scenarios:

1. **App installed** → User clicks link → app opens directly with link data
2. **App not installed** → User clicks link → redirected to store → installs → app opens with original link data (deferred deep linking)

**Backend:** [ae-link-backend](https://github.com/DabhiNavaghan/ae-link-backend)
**SDK Repo:** [ae-link](https://github.com/DabhiNavaghan/ae-link)
**Dashboard:** [aelink.vercel.app](https://aelink.vercel.app)

## Setup

### 1. Add dependency

```yaml
# pubspec.yaml
dependencies:
  ae_link:
    git:
      url: https://github.com/DabhiNavaghan/ae-link.git
```

### 2. Register your app in the dashboard

Go to [aelink.vercel.app/dashboard/apps](https://aelink.vercel.app/dashboard/apps) and add your app with:

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

    <!-- AE-LINK App Links — opens your app when link is clicked -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="aelink.vercel.app" />
    </intent-filter>
</activity>
```

Replace `aelink.vercel.app` with your deployment domain if different.

**How it works:** Android checks `https://aelink.vercel.app/.well-known/assetlinks.json` to verify your app is authorized to handle links from this domain. The backend generates this file automatically from your registered app's package name and SHA-256.

**Get your SHA-256 fingerprint:**
```bash
cd android
./gradlew signingReport
# Look for "SHA-256" under your signing config
```

### 4. iOS — Universal Links setup

**Step 1:** In Xcode, go to your target → Signing & Capabilities → add "Associated Domains" and add:

```
applinks:aelink.vercel.app
```

**Step 2:** That's it. The backend serves `/.well-known/apple-app-site-association` automatically from your registered app's Team ID and Bundle ID.

**How it works:** iOS checks the AASA file on your domain to verify your app is authorized to handle links. The backend generates this from your registered iOS config.

### 5. Initialize the SDK

Create `lib/services/aelink_service.dart`:

```dart
import 'package:ae_link/ae_link.dart';
import 'package:flutter/material.dart';

late AeLinkService aeLink;

Future<DeepLinkData?> initAeLink({
  required GlobalKey<NavigatorState> navigatorKey,
  bool isExistingUser = false,
}) async {
  aeLink = AeLinkService(
    apiKey: 'YOUR_API_KEY',  // From dashboard Settings
    debug: true,              // false in production
    isExistingUser: isExistingUser,  // true if user already has the app
    onDeepLink: (data) {
      _handleDeepLink(data, navigatorKey);
    },
  );

  return await aeLink.initialize();
}

void _handleDeepLink(DeepLinkData data, GlobalKey<NavigatorState> navKey) {
  final navigator = navKey.currentState;
  if (navigator == null) return;

  debugPrint('AE-LINK: eventId=${data.eventId}, action=${data.action}, '
      'deferred=${data.isDeferred}');

  if (data.eventId != null) {
    navigator.pushNamed('/event/${data.eventId}');
  }
}
```

Then in `main.dart`:

```dart
import 'services/aelink_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pass isExistingUser: true if user is already logged in
  // (prevents existing users from being counted as new installs)
  final deferred = await initAeLink(
    navigatorKey: navigatorKey,
    isExistingUser: false,  // or: await isUserLoggedIn()
  );

  runApp(MyApp(
    navigatorKey: navigatorKey,
    initialDeepLink: deferred,
  ));
}
```

## What the SDK does on each launch

**First launch after install:**
```
[I] [AE-LINK] Initializing AE-LINK SDK...
[I] [AE-LINK] Launch: first_install
[I] [AE-LINK] SDK ready
[I] [AE-LINK] First launch — checking deferred link...
[I] [AE-LINK] Deferred link matched: abc123    ← or "No deferred link (organic install)"
```

**App already installed, user clicks a link:**
```
[I] [AE-LINK] Initializing AE-LINK SDK...
[I] [AE-LINK] Launch: return_user
[I] [AE-LINK] SDK ready
[I] [AE-LINK] Deep link received: https://aelink.vercel.app/xGJEQJR
```

**Reinstall:**
```
[I] [AE-LINK] Launch: reinstall
[I] [AE-LINK] First launch — checking deferred link...
```

## Available data in DeepLinkData

```dart
onDeepLink: (data) {
  data.eventId;          // "12345"
  data.action;           // "view_event", "buy_ticket"
  data.destinationUrl;   // "https://allevents.in/event/..."
  data.isDeferred;       // true if from deferred matching
  data.deferredLinkId;   // ID for tracking
  data.linkId;           // Original link ID

  // UTM params
  data.linkParams?.utmSource;    // "email"
  data.linkParams?.utmCampaign;  // "summer-promo"

  // Special params
  data.couponCode;       // "SAVE20"
  data.referralCode;     // "REF123"
  data.userEmail;        // "user@example.com"
}
```

## Troubleshooting

**"App doesn't open when I click the link"**
- Make sure you registered the app in the dashboard with the correct package name and SHA-256
- Verify `assetlinks.json` is served: visit `https://aelink.vercel.app/.well-known/assetlinks.json`
- On Android: run `adb shell pm get-app-links com.yourpackage` to check verification status
- On iOS: check Associated Domains is enabled in Xcode with `applinks:aelink.vercel.app`

**"Deferred link not matching"**
- Uninstall the app completely before testing (SharedPreferences must be cleared)
- Click the link in a browser first, then install the app within 72 hours
- Enable `debug: true` to see matching logs
- The match requires 60+ points. Same WiFi network = 40 points (IP match)

**"Launch: first_install but user already had the app"**
- Set `isExistingUser: true` for logged-in users when adding the SDK to an existing app

## License

See LICENSE file.
