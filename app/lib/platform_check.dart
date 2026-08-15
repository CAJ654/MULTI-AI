// Real, OS-level "is this genuinely Android" — deliberately *not*
// `defaultTargetPlatform` (package:flutter/foundation.dart), which the
// `flutter_test` binding overrides to `TargetPlatform.android` by default
// regardless of the host OS (a rendering-consistency choice for widget
// tests, confirmed by probing it directly under `flutter test` on this
// Windows dev machine). Code that decides "does this device have a real
// backend/on-device storage" needs the actual host, not that simulated
// value, or every widget test would silently take the Android-only branch.
//
// Uses a conditional import instead of `dart:io` directly so this stays
// importable from files that must also compile for web (`dart:io` fails
// outright there) — same reasoning as `api_client.dart`'s
// `defaultTargetPlatform`/`kIsWeb` use, just for a check that must be
// test-safe too.
export 'platform_check_stub.dart' if (dart.library.io) 'platform_check_io.dart';
