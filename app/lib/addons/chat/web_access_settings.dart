import 'dart:convert';

import '../../chat_store.dart' show appDataFile;

/// Whether the user has already seen the one-time "what leaves your device"
/// explainer for Chat's web-search toggle — see `chat_addon.dart`. The
/// toggle's on/off state itself is deliberately *not* persisted here: each
/// launch starts with web access off, matching an opt-in-every-time posture
/// rather than a sticky one.
class WebAccessSettings {
  WebAccessSettings({required this.explainerSeen});

  final bool explainerSeen;

  factory WebAccessSettings.defaults() => WebAccessSettings(explainerSeen: false);

  Map<String, dynamic> toJson() => {'explainerSeen': explainerSeen};

  factory WebAccessSettings.fromJson(Map<String, dynamic> json) =>
      WebAccessSettings(explainerSeen: json['explainerSeen'] as bool? ?? false);
}

/// Where web-access settings are persisted — same shape as
/// `ThinkingSettingsStore` (`thinking_settings.dart`): [FileWebAccessSettingsStore]
/// is the real, file-backed implementation, [InMemoryWebAccessSettingsStore]
/// stands in for tests and any platform where the real one can't write.
abstract class WebAccessSettingsStore {
  Future<WebAccessSettings> load();
  Future<void> save(WebAccessSettings settings);
}

/// Persists as `web_access_settings.json` alongside chat history — see
/// `appDataFile` in `chat_store.dart` for the shared directory.
class FileWebAccessSettingsStore implements WebAccessSettingsStore {
  @override
  Future<WebAccessSettings> load() async {
    try {
      final file = await appDataFile('web_access_settings.json');
      if (!await file.exists()) return WebAccessSettings.defaults();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WebAccessSettings.fromJson(data);
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means defaults.
      return WebAccessSettings.defaults();
    }
  }

  @override
  Future<void> save(WebAccessSettings settings) async {
    try {
      final file = await appDataFile('web_access_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Persistence is best-effort; the in-memory settings still work.
    }
  }
}

/// In-memory store for tests and for any platform where the real one can't
/// write. Behaves like a file that starts at defaults.
class InMemoryWebAccessSettingsStore implements WebAccessSettingsStore {
  WebAccessSettings _settings = WebAccessSettings.defaults();

  @override
  Future<WebAccessSettings> load() async => _settings;

  @override
  Future<void> save(WebAccessSettings settings) async => _settings = settings;
}
