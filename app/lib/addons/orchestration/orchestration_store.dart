import 'dart:convert';
import 'dart:io';

import '../../chat_store.dart' show appDataFile;
import 'orchestration_controller.dart';

/// Where past council runs are persisted. [FileOrchestrationStore] is the
/// real, file-backed implementation; [InMemoryOrchestrationStore] stands in
/// for tests and any platform where the real one can't write — mirrors
/// `ChatStore` in `chat_store.dart`.
abstract class OrchestrationStore {
  Future<List<OrchestrationSession>> load();
  Future<void> save(List<OrchestrationSession> sessions);
}

/// Persists council runs as a JSON file in the app's data directory, so past
/// runs survive restarts until the user explicitly deletes them.
class FileOrchestrationStore implements OrchestrationStore {
  // Chains writes so a save never interleaves with a previous one.
  Future<void> _lastWrite = Future.value();

  Future<File> _file() => appDataFile('orchestration_sessions.json');

  @override
  Future<List<OrchestrationSession>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (data['sessions'] as List<dynamic>)
          .map((s) => OrchestrationSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A missing plugin (tests) or corrupt file just means no history.
      return [];
    }
  }

  @override
  Future<void> save(List<OrchestrationSession> sessions) {
    // Snapshot now, before awaiting, so the write reflects this call's state.
    final payload = jsonEncode({
      'sessions': [
        for (final s in sessions)
          if (s.hasRun) s.toJson(),
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
class InMemoryOrchestrationStore implements OrchestrationStore {
  List<OrchestrationSession> _sessions = const [];

  @override
  Future<List<OrchestrationSession>> load() async => _sessions;

  @override
  Future<void> save(List<OrchestrationSession> sessions) async {
    _sessions = [
      for (final s in sessions)
        if (s.hasRun) s,
    ];
  }
}
