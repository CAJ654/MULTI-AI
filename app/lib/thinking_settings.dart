import 'dart:convert';

import 'chat_store.dart' show appDataFile;
import 'thinking_words.dart';

/// Which "thinking" phrase groups are in rotation, and which individual
/// phrases within an enabled group are excluded. A group toggle is a master
/// switch; per-phrase exclusions only matter while that group is enabled.
class ThinkingSettings {
  ThinkingSettings({required this.enabledGroups, required this.disabledWords});

  final Set<String> enabledGroups;
  final Map<String, Set<String>> disabledWords;

  /// Ships with the "Classic" group on (recreates the familiar Claude Code
  /// spinner) and the others off, so the feature is visible out of the box
  /// without being loud about it.
  factory ThinkingSettings.defaults() => ThinkingSettings(enabledGroups: {'classic'}, disabledWords: {});

  /// All enabled words across all enabled groups, flattened for the rotating
  /// indicator to pick from. Empty means "show the plain static message".
  List<String> get activeWords => [
        for (final group in thinkingWordGroups)
          if (enabledGroups.contains(group.id))
            for (final word in group.words)
              if (!(disabledWords[group.id]?.contains(word) ?? false)) word,
      ];

  bool isWordEnabled(String groupId, String word) => !(disabledWords[groupId]?.contains(word) ?? false);

  Map<String, dynamic> toJson() => {
        'enabledGroups': enabledGroups.toList(),
        'disabledWords': {for (final e in disabledWords.entries) e.key: e.value.toList()},
      };

  factory ThinkingSettings.fromJson(Map<String, dynamic> json) => ThinkingSettings(
        enabledGroups: {...(json['enabledGroups'] as List<dynamic>? ?? []).cast<String>()},
        disabledWords: {
          for (final e in (json['disabledWords'] as Map<String, dynamic>? ?? {}).entries)
            e.key: {...(e.value as List<dynamic>).cast<String>()},
        },
      );
}

/// Where thinking-indicator settings are persisted. [FileThinkingSettingsStore]
/// is the real, file-backed implementation; [InMemoryThinkingSettingsStore]
/// stands in for tests and any platform where the real one can't write.
abstract class ThinkingSettingsStore {
  Future<ThinkingSettings> load();
  Future<void> save(ThinkingSettings settings);
}

/// Persists thinking-indicator settings as a JSON file alongside chat
/// history — see `appDataFile` in `chat_store.dart` for the shared directory.
class FileThinkingSettingsStore implements ThinkingSettingsStore {
  @override
  Future<ThinkingSettings> load() async {
    try {
      final file = await appDataFile('thinking_settings.json');
      if (!await file.exists()) return ThinkingSettings.defaults();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ThinkingSettings.fromJson(data);
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means defaults.
      return ThinkingSettings.defaults();
    }
  }

  @override
  Future<void> save(ThinkingSettings settings) async {
    try {
      final file = await appDataFile('thinking_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Persistence is best-effort; the in-memory settings still work.
    }
  }
}

/// In-memory store for tests and for any platform where the real one can't
/// write. Behaves like a file that starts at defaults.
class InMemoryThinkingSettingsStore implements ThinkingSettingsStore {
  ThinkingSettings _settings = ThinkingSettings.defaults();

  @override
  Future<ThinkingSettings> load() async => _settings;

  @override
  Future<void> save(ThinkingSettings settings) async => _settings = settings;
}
