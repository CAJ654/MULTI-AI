import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';

import '../../chat_store.dart' show appDataFile;
import 'code_agent_controller.dart';

/// One Code tab conversation: its display transcript plus the underlying
/// [AgentState] the model actually sees. Persisting [agentState] (not just
/// the transcript) is what lets picking a past conversation back up actually
/// continue it with full context, rather than just replaying a read-only log.
class CodeSession {
  CodeSession({this.title, List<CodeTranscriptEntry>? transcript, AgentState? agentState})
      : transcript = transcript ?? [],
        agentState = agentState ?? AgentState.empty();

  String? title;
  final List<CodeTranscriptEntry> transcript;
  AgentState agentState;

  /// The project folder and model this conversation last ran against — shown
  /// in the sidebar, not used to auto-switch the live picker when a past
  /// session is selected.
  String? projectRoot;
  String? modelId;
  String? modelName;

  /// How the run this session was last part of ended, if it failed. Mirrors
  /// `OrchestrationSession.error` — kept per session so switching away from a
  /// failed conversation doesn't leave a stale error banner on another one.
  String? error;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        'transcript': transcript.map((e) => e.toJson()).toList(),
        'agentState': agentState.toJson(),
        if (projectRoot != null) 'projectRoot': projectRoot,
        if (modelId != null) 'modelId': modelId,
        if (modelName != null) 'modelName': modelName,
        if (error != null) 'error': error,
      };

  factory CodeSession.fromJson(Map<String, dynamic> json) {
    final session = CodeSession(
      title: json['title'] as String?,
      transcript: [
        for (final e in (json['transcript'] as List<dynamic>? ?? []))
          ?codeTranscriptEntryFromJson(e as Map<String, dynamic>),
      ],
      agentState: AgentState.fromJson(json['agentState'] as Map<String, dynamic>),
    )
      ..projectRoot = json['projectRoot'] as String?
      ..modelId = json['modelId'] as String?
      ..modelName = json['modelName'] as String?
      ..error = json['error'] as String?;
    return session;
  }
}

/// Where past Code tab conversations are persisted. [FileCodeSessionStore] is
/// the real, file-backed implementation; [InMemoryCodeSessionStore] stands in
/// for tests and any platform where the real one can't write — mirrors
/// `ChatStore` in `chat_store.dart`.
abstract class CodeSessionStore {
  Future<List<CodeSession>> load();
  Future<void> save(List<CodeSession> sessions);
}

class FileCodeSessionStore implements CodeSessionStore {
  // Chains writes so a save never interleaves with a previous one.
  Future<void> _lastWrite = Future.value();

  Future<File> _file() => appDataFile('code_sessions.json');

  @override
  Future<List<CodeSession>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (data['sessions'] as List<dynamic>)
          .map((s) => CodeSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means no history.
      return [];
    }
  }

  @override
  Future<void> save(List<CodeSession> sessions) {
    // Snapshot now, before awaiting, so the write reflects this call's state.
    final payload = jsonEncode({
      'sessions': [
        for (final s in sessions)
          if (s.transcript.isNotEmpty) s.toJson(),
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

/// In-memory store for tests and for any platform where the real one can't
/// write. Behaves like a file that starts empty.
class InMemoryCodeSessionStore implements CodeSessionStore {
  List<CodeSession> _sessions = const [];

  @override
  Future<List<CodeSession>> load() async => _sessions;

  @override
  Future<void> save(List<CodeSession> sessions) async {
    _sessions = [
      for (final s in sessions)
        if (s.transcript.isNotEmpty) s,
    ];
  }
}
