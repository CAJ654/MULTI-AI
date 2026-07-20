import 'dart:convert';
import 'dart:io';

/// How chat bubbles treat markdown in their text.
///
/// Assistant replies are always rendered — models emit `**bold**`, bullet
/// lists and fenced code as a matter of course, and showing that raw is just a
/// bug. The user's own messages are a different question: text you typed
/// should normally appear as you typed it, so rendering there is opt-in.
class MarkdownSettings {
  const MarkdownSettings({required this.renderUserMessages});

  /// Whether the user's own bubbles render markdown rather than showing it
  /// literally. Off by default — see the class doc.
  final bool renderUserMessages;

  factory MarkdownSettings.defaults() => const MarkdownSettings(renderUserMessages: false);

  MarkdownSettings copyWith({bool? renderUserMessages}) =>
      MarkdownSettings(renderUserMessages: renderUserMessages ?? this.renderUserMessages);

  Map<String, dynamic> toJson() => {'renderUserMessages': renderUserMessages};

  factory MarkdownSettings.fromJson(Map<String, dynamic> json) =>
      MarkdownSettings(renderUserMessages: json['renderUserMessages'] as bool? ?? false);
}

/// Persists [MarkdownSettings] as a JSON file alongside chat history and the
/// thinking-indicator settings — same env-var-resolved directory and the same
/// no-path_provider reasoning (that plugin needs Windows Developer Mode to
/// build, which this app otherwise doesn't require).
class MarkdownSettingsStore {
  Future<File> _file() async {
    final env = Platform.environment;
    String? base;
    if (Platform.isWindows) {
      base = env['APPDATA'];
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null) base = '$home/Library/Application Support';
    } else {
      base = env['XDG_DATA_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.local/share' : null);
    }
    final sep = Platform.pathSeparator;
    final dir = Directory(base != null ? '$base${sep}multi_ai' : '.multi_ai_data');
    await dir.create(recursive: true);
    return File('${dir.path}${sep}markdown_settings.json');
  }

  Future<MarkdownSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return MarkdownSettings.defaults();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return MarkdownSettings.fromJson(data);
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means defaults.
      return MarkdownSettings.defaults();
    }
  }

  Future<void> save(MarkdownSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Persistence is best-effort; the in-memory settings still work.
    }
  }
}
