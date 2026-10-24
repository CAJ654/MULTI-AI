import 'dart:convert';
import 'dart:math';

import '../../chat_store.dart' show appDataFile;

/// Default loopback port for the Antigravity endpoint. Clear of the backend
/// (8000), Colibri (8010) and the Code add-on's llama-server/opencode
/// (8100/8101).
const antigravityDefaultPort = 8200;

/// What the Antigravity add-on remembers between launches.
///
/// [bearerToken] sits in plaintext in the JSON file, like every other setting
/// here — the app has no secure store. That's acceptable for a token that only
/// guards a loopback-only server: anything able to read this file already runs
/// as the user and could read the model weights directly.
class AntigravitySettings {
  const AntigravitySettings({
    required this.port,
    required this.modelId,
    required this.autoStart,
    required this.bearerToken,
  });

  final int port;

  /// The model a request falls back to when it names none the pool knows.
  /// Null until the user picks one.
  final String? modelId;

  /// Whether the server starts by itself when the add-on is enabled. Off by
  /// default: exposing the models should be an explicit act.
  final bool autoStart;

  final String bearerToken;

  factory AntigravitySettings.defaults() => AntigravitySettings(
        port: antigravityDefaultPort,
        modelId: null,
        autoStart: false,
        bearerToken: generateBearerToken(),
      );

  AntigravitySettings copyWith({
    int? port,
    String? modelId,
    bool? autoStart,
    String? bearerToken,
  }) =>
      AntigravitySettings(
        port: port ?? this.port,
        modelId: modelId ?? this.modelId,
        autoStart: autoStart ?? this.autoStart,
        bearerToken: bearerToken ?? this.bearerToken,
      );

  Map<String, dynamic> toJson() => {
        'port': port,
        'modelId': modelId,
        'autoStart': autoStart,
        'bearerToken': bearerToken,
      };

  factory AntigravitySettings.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    final token = json['bearerToken'];
    return AntigravitySettings(
      port: port is int && port > 0 && port < 65536 ? port : antigravityDefaultPort,
      modelId: json['modelId'] as String?,
      autoStart: json['autoStart'] as bool? ?? false,
      // A missing/empty token is regenerated rather than left blank — a blank
      // one would make the server's auth check meaningless.
      bearerToken: token is String && token.isNotEmpty ? token : generateBearerToken(),
    );
  }
}

/// 32 random bytes from the OS CSPRNG, hex-encoded.
String generateBearerToken() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Where the Antigravity settings are persisted — same shape as
/// `WebAccessSettingsStore` (`chat/web_access_settings.dart`):
/// [FileAntigravitySettingsStore] is the real one, [InMemoryAntigravitySettingsStore]
/// stands in for tests.
abstract class AntigravitySettingsStore {
  Future<AntigravitySettings> load();
  Future<void> save(AntigravitySettings settings);
}

/// Persists as `antigravity_settings.json` — see `appDataFile` in
/// `chat_store.dart` for the shared directory.
class FileAntigravitySettingsStore implements AntigravitySettingsStore {
  @override
  Future<AntigravitySettings> load() async {
    try {
      final file = await appDataFile('antigravity_settings.json');
      if (!await file.exists()) return AntigravitySettings.defaults();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AntigravitySettings.fromJson(data);
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means defaults.
      return AntigravitySettings.defaults();
    }
  }

  @override
  Future<void> save(AntigravitySettings settings) async {
    try {
      final file = await appDataFile('antigravity_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Persistence is best-effort; the in-memory settings still work.
    }
  }
}

/// In-memory store for tests. Behaves like a file that starts at defaults —
/// including generating its token once, so [load] is stable across calls.
class InMemoryAntigravitySettingsStore implements AntigravitySettingsStore {
  AntigravitySettings _settings = AntigravitySettings.defaults();

  @override
  Future<AntigravitySettings> load() async => _settings;

  @override
  Future<void> save(AntigravitySettings settings) async => _settings = settings;
}
