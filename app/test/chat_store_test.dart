import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:multi_ai/chat_store.dart';

/// Fakes path_provider's plugin channel so appDataFile() can be exercised
/// against real (temp) disk without a real platform behind it — this is the
/// one test that would have caught the original Android bug (an empty
/// Platform.environment silently resolving to an unwritable relative path),
/// since it's the only test in this suite that touches actual file IO for
/// this code path rather than an in-memory double.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  group('appDataFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('multi_ai_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('resolves under the fake support directory and round-trips a write', () async {
      final file = await appDataFile('probe.json');
      expect(file.path, startsWith(tempDir.path));

      await file.writeAsString('{"ok":true}');
      expect(await file.readAsString(), '{"ok":true}');
    });
  });


  test('chat sessions survive a JSON round-trip', () {
    final session = ChatSession(title: 'Fun fact', messages: [
      const ChatMessage(text: 'Tell me a fun fact', isUser: true),
      const ChatMessage(text: 'Rome had concrete.', isUser: false, sender: 'Falcon3'),
      const ChatMessage(text: 'backend unreachable', isUser: false, sender: 'Falcon3', isError: true),
    ]);

    final restored = ChatSession.fromJson(session.toJson());

    expect(restored.title, 'Fun fact');
    expect(restored.messages.length, 3);
    expect(restored.messages[0].text, 'Tell me a fun fact');
    expect(restored.messages[0].isUser, isTrue);
    expect(restored.messages[1].sender, 'Falcon3');
    expect(restored.messages[1].isError, isFalse);
    expect(restored.messages[2].isError, isTrue);
  });

  test('untitled session round-trips with a null title', () {
    final restored = ChatSession.fromJson(ChatSession().toJson());
    expect(restored.title, isNull);
    expect(restored.messages, isEmpty);
  });
}
