# SmartLink Flutter SDK

Flutter SDK for deep linking with the SmartLink platform. Handles two separate scenarios with separate callbacks:

1. **Direct Deep Link** (`onDeepLink`) → App is installed, user clicks a link, app opens with link data
2. **Deferred Deep Link** (`onDeferredDeepLink`) → App is NOT installed, user clicks link → store → installs → first launch delivers the original link data

It also tracks what people do *after* they install — see
[Event Tracking](#event-tracking) for `track()`, `identify()` and `logout()`.

**Backend:** [smartlink-backend](https://github.com/DabhiNavaghan/ae-link-backend)
**SDK Repo:** [smartlink](https://github.com/DabhiNavaghan/ae-link)
**Dashboard:** [smartlink.apps.allevents.app](https://smartlink.apps.allevents.app)

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
        <data android:scheme="https" android:host="smartlink.apps.allevents.app" />
    </intent-filter>
</activity>
```

Replace the host with your deployment domain if different.

### 4. iOS — Universal Links setup

In Xcode, go to your target → Signing & Capabilities → add "Associated Domains" and add:

```
applinks:smartlink.apps.allevents.app
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
    apiBaseUrl: 'https://smartlink.apps.allevents.app',
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
- User clicks a SmartLink URL (e.g., `https://smartlink.apps.allevents.app/xGJEQJR`)
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

## Event Tracking

Deep linking tells you a link was clicked and an app was installed. Event
tracking tells you what happened next, and which link earned it.

### Track an event

```dart
await smartLink.track(
  'ticket_purchase',
  value: 1250,
  currency: 'INR',
  properties: {'event_id': 'evt_991', 'qty': 2},
);
```

Returns as soon as the event is on disk. The SDK batches and sends in the
background, survives a cold start, and flushes when connectivity returns. It
never throws for network reasons — a checkout must not fail because analytics did.

**Event names** must match `^[a-z][a-z0-9_]{0,63}$` — lowercase letters, digits
and underscores. Names are a small fixed vocabulary, so put ids, titles and other
varying values in `properties`, never in the name. A tenant is capped at 200
distinct names; hitting that usually means a value was sent as a name by mistake.

**Do not put personal data in `properties`.** The server drops keys that look
like emails, phone numbers, names or card details, and reports the drop back so
it surfaces during integration rather than in an audit. Use `identify()` for
anything about a person.

### Identify a user on sign-in

```dart
await smartLink.identify('u_88213', traits: {'plan': 'pro'});
```

Everything tracked after this carries the user. Events tracked *before* it on this
device are backfilled onto them server-side — those were the same person browsing
before they signed in.

The first `identify()` also fixes the user's **acquisition source**: the link and
campaign that brought them in, permanently, across every device they later sign in
on. Later sign-ins never overwrite it.

Only trait keys your tenant has allowlisted are stored. `email` is hashed before
storage unless your tenant has explicitly opted into plaintext.

### Sign out

```dart
await smartLink.logout();
```

Keeps `deviceId` deliberately. Rotating it would sever install attribution and
make the next launch look like a fresh install, re-counting it. The server starts
a new identity epoch instead, which is what stops the next person signing in on a
shared device from inheriting the previous user's history.

### Flush before a known exit

```dart
await smartLink.flush();
```

### Automatic events

Emitted without you writing any tracking code, so a funnel exists on day one:

| Event | When |
|---|---|
| `app_install` | First launch after install |
| `app_open` | Every launch |
| `session_start` | New session (after 30 min backgrounded) |
| `deep_link_opened` | A SmartLink URL opened the app |
| `user_identified` | `identify()` succeeded |
| `user_logged_out` | `logout()` was called |

Turn them off with `enableAutomaticEvents: false`.

### Opting out of tracking entirely

```dart
smartLink = SmartLink(
  apiKey: 'YOUR_API_KEY',
  enableEventTracking: false,   // honours a user's analytics opt-out
);
```

Deep linking and attribution keep working.

### Inspecting the queue

```dart
smartLink.currentUserId;       // who this device is signed in as, or null
smartLink.queuedEventCount;    // still waiting to send
smartLink.droppedEventCount;   // lost to queue overflow or exhausted retries
```

`droppedEventCount` being non-zero means data was lost. It is exposed rather than
hidden so you can surface it in a debug screen.

### Revenue you can bill on

Your API key ships inside your app binary, so anyone who decompiles the app has
it. Revenue sent with it is fine for product analytics and **not** sufficient for
billing or partner payouts. For money that matters, send the event from your own
backend using your tenant key, or HMAC-sign it. Ask your platform admin to enable
`requireSignedRevenue`, after which unsigned monetary events are rejected rather
than quietly recorded.

## Log Levels

The SDK uses an integer-based log level system:

| Level | Name | Use For |
|-------|------|---------|
| `-1` | Verbose | Extra detail for deep debugging |
| `0` | Minimal debug | Actions + results only — good for development |
| `1` | Release | Silent — no logs (default) |

**logLevel: 0 (minimal debug) — development:**
```
[SmartLink] INFO  Initializing SmartLink SDK...
[SmartLink] INFO  Launch: first_install
[SmartLink] INFO  SDK ready
[SmartLink] INFO  First launch — checking deferred link...
[SmartLink] INFO  Collecting fingerprint...
[SmartLink] INFO  ✅ Fingerprint collected
[SmartLink] INFO  ✅ DEFERRED LINK MATCHED! Score: 100
[SmartLink] INFO  Deferred link matched: abc123
```

**Direct deep link (app already installed):**
```
[SmartLink] INFO  Deep link received
[SmartLink] INFO  ✅ Deep link resolved
```

**logLevel: -1 (verbose) — deep debugging:**
Same as above, plus link data, campaign data, and params:
```
[SmartLink] INFO  ✅ DEFERRED LINK MATCHED! Score: 95
[SmartLink] DATA  deferred_link → deferredLinkId: abc123 | linkId: lnk_456 | eventId: 789 | action: view_event | destinationUrl: https://allevents.in/event/789
[SmartLink] DATA  campaign → campaignId: camp_001 | campaignName: summer-promo
[SmartLink] DATA  params → utmSource: email | utmCampaign: summer-promo | couponCode: SAVE20
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
