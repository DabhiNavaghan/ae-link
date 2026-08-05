# Changelog

All notable changes to the AE-LINK Flutter SDK will be documented in this file.

## [1.1.0] - 2026-07-30

Event and user tracking. The funnel used to stop at install; it now continues
through to whatever people do next, attributed to the link that brought them.

### Added
- **`track()`** — queue a product event with optional revenue and properties:
  ```dart
  await smartLink.track('ticket_purchase',
      value: 1250, currency: 'INR',
      properties: {'event_id': 'evt_991', 'qty': 2});
  ```
- **`identify()`** — attach the device to a signed-in user. Events tracked
  earlier on this device are backfilled onto them server-side, and the first
  call permanently records which link and campaign acquired them.
- **`logout()`** — end the session. Keeps `deviceId` deliberately; rotating it
  would sever install attribution and re-count the install.
- **`flush()`** — send the queue now, for use before a known exit.
- **`currentUserId`**, **`queuedEventCount`**, **`droppedEventCount`** getters.
- **Automatic events** (opt out with `enableAutomaticEvents: false`):
  `app_install`, `app_open`, `session_start`, `deep_link_opened`,
  `user_identified`, `user_logged_out`.
- **`enableEventTracking`** flag to disable tracking entirely, for honouring a
  user's analytics opt-out. Deep linking is unaffected.
- `TrackedEvent` model and `TrackingService`.
- Test suite for the queue: persistence, overflow, retry, backoff, session
  rotation, offline identify replay.

### Implementation notes
- **Queue is on disk**, so events survive a cold start; capped at 1000 and drops
  oldest-first with a counter rather than growing unbounded.
- **Idempotency keys are minted at enqueue**, not at send, so a retry after an
  ambiguous network failure is provably the same event and the server collapses
  it to a no-op.
- **Batches of 50**, flushed on size or a 30s interval, with exponential backoff
  and jitter — without jitter every device that lost connectivity retries in
  lockstep when it returns.
- An event is dropped after 10 failed attempts, so one undeliverable event can't
  block the queue behind it forever.
- Sessions rotate after 30 minutes backgrounded, matching the industry
  convention so the numbers are comparable with other tools.
- `identify()` is persisted and replayed, so signing in offline still works.

### Changed
- `SmartLinkConfig` gained `enableEventTracking` and `enableAutomaticEvents`.
  Both default to `true`; existing integrations need no changes.

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
