import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/antigravity/antigravity_settings.dart';

void main() {
  test('defaults: default port, auto-start off, a generated token', () {
    final settings = AntigravitySettings.defaults();
    expect(settings.port, antigravityDefaultPort);
    expect(settings.autoStart, isFalse);
    expect(settings.modelId, isNull);
    expect(settings.bearerToken, hasLength(64));
  });

  test('tokens are random', () {
    expect(generateBearerToken(), isNot(generateBearerToken()));
  });

  test('round-trips through JSON', () {
    final original = AntigravitySettings.defaults().copyWith(port: 9000, modelId: 'm', autoStart: true);
    final restored = AntigravitySettings.fromJson(original.toJson());
    expect(restored.port, 9000);
    expect(restored.modelId, 'm');
    expect(restored.autoStart, isTrue);
    expect(restored.bearerToken, original.bearerToken);
  });

  test('bad JSON values fall back: invalid port, empty token regenerated', () {
    final restored = AntigravitySettings.fromJson({'port': 99999, 'bearerToken': ''});
    expect(restored.port, antigravityDefaultPort);
    expect(restored.bearerToken, hasLength(64));
  });

  test('the in-memory store keeps one token across loads', () async {
    final store = InMemoryAntigravitySettingsStore();
    expect((await store.load()).bearerToken, (await store.load()).bearerToken);
  });
}
