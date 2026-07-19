import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/chat_store.dart';

void main() {
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
