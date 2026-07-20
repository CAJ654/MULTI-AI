import 'dart:convert';

/// Value types shared by the two chat backends — the HTTP client in
/// `api_client.dart` and the local llama.cpp engine in `on_device_engine.dart`.
///
/// They live apart from `api_client.dart` because that file imports
/// `package:flutter/foundation.dart` (for the per-platform base URL), and the
/// on-device engine has to stay importable from plain `dart run` — the
/// verification harness in `tool/verify_on_device.dart` drives the real engine
/// headlessly, with no Flutter binding in sight. Nothing here needs more than
/// `dart:convert`. `api_client.dart` re-exports the lot, so every existing
/// import site is unaffected.

/// Kind of non-text input a message carries. The wire values match the
/// backend's `_INPUT_MODALITIES` tokens.
enum AttachmentKind {
  image('image'),
  audio('audio');

  const AttachmentKind(this.wireName);

  final String wireName;

  static AttachmentKind? fromWireName(String name) {
    for (final kind in AttachmentKind.values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }
}

/// One image or audio clip attached to an outgoing message. Held in memory as
/// bytes rather than a path: a recording lives in a temp file the OS may clear,
/// and the chat history needs to still render it afterwards.
class Attachment {
  const Attachment({
    required this.kind,
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final AttachmentKind kind;
  final List<int> bytes;
  final String mimeType;
  final String name;

  Map<String, dynamic> toWireJson() => {
        'kind': kind.wireName,
        'mime_type': mimeType,
        'name': name,
        'data': base64Encode(bytes),
      };
}

/// One prior turn of a conversation, sent so the model can see what was
/// already said. The UI shows a threaded chat, so without this the model
/// would answer every message as if it were the first.
class ChatTurn {
  const ChatTurn({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  Map<String, dynamic> toWireJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
}
