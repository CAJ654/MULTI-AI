import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.sender,
    this.isError = false,
    this.attachments = const [],
  });

  final String text;
  final bool isUser;
  final String? sender;
  final bool isError;

  /// Images/audio the user sent alongside [text]. Always empty on replies —
  /// the models here only produce text.
  final List<Attachment> attachments;

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        if (sender != null) 'sender': sender,
        if (isError) 'isError': isError,
        // Base64 in the same file as the text: attachments are capped at 32MB
        // server-side and this keeps history a single self-contained blob,
        // with no second store to keep in sync when a chat is deleted.
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) a.toWireJson()],
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String,
        isUser: json['isUser'] as bool,
        sender: json['sender'] as String?,
        isError: json['isError'] as bool? ?? false,
        attachments: [
          for (final a in (json['attachments'] as List<dynamic>? ?? []))
            ?_attachmentFromJson(a as Map<String, dynamic>),
        ],
      );
}

/// Null for an entry whose `kind` this build doesn't know — a history file
/// written by a newer version shouldn't make the whole chat fail to load.
Attachment? _attachmentFromJson(Map<String, dynamic> json) {
  final kind = AttachmentKind.fromWireName(json['kind'] as String? ?? '');
  if (kind == null) return null;
  return Attachment(
    kind: kind,
    bytes: base64Decode(json['data'] as String),
    mimeType: json['mime_type'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );
}

class ChatSession {
  ChatSession({this.title, List<ChatMessage>? messages}) : messages = messages ?? [];

  String? title;
  final List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        title: json['title'] as String?,
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// Persists chat sessions as a JSON file in the app's data directory, so
/// chats survive restarts until the user explicitly deletes them.
class ChatStore {
  // Chains writes so a save never interleaves with a previous one.
  Future<void> _lastWrite = Future.value();

  // Resolved from environment variables instead of path_provider: the plugin
  // needs Windows Developer Mode (symlinks) to build, which this app otherwise
  // doesn't require.
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
    return File('${dir.path}${sep}chat_sessions.json');
  }

  Future<List<ChatSession>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (data['sessions'] as List<dynamic>)
          .map((s) => ChatSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means no history.
      return [];
    }
  }

  Future<void> save(List<ChatSession> sessions) {
    // Snapshot now, before awaiting, so the write reflects this call's state.
    final payload = jsonEncode({
      'sessions': [
        for (final s in sessions)
          if (s.messages.isNotEmpty) s.toJson(),
      ],
    });
    return _lastWrite = _lastWrite.then((_) async {
      try {
        final file = await _file();
        await file.writeAsString(payload);
      } catch (_) {
        // Persistence is best-effort; the in-memory session still works.
      }
    });
  }
}
