import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tool_approval.dart';

/// One decoded event from opencode's `/event` SSE stream, narrowed to the
/// kinds `CodeAgentController` acts on. Everything else opencode emits
/// (`session.updated`, `server.heartbeat`, `session.status`, ...) is dropped
/// by [OpencodeEvent.tryParse] rather than modeled here — confirmed against
/// a running `opencode serve` (its OpenAPI spec lists 80+ event types; most
/// don't concern a single-session, single-project tab like this one).
sealed class OpencodeEvent {
  const OpencodeEvent(this.sessionId);

  final String sessionId;

  /// Returns null for an event type this client doesn't act on, or a
  /// malformed payload — a forward-compat opencode release adding new event
  /// types shouldn't crash the stream, it should just be ignored.
  static OpencodeEvent? tryParse(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final props = json['properties'] as Map<String, dynamic>?;
    if (type == null || props == null) return null;
    final sessionId = props['sessionID'] as String?;
    switch (type) {
      case 'message.part.updated':
        if (sessionId == null) return null;
        final part = props['part'] as Map<String, dynamic>?;
        if (part == null) return null;
        return OpencodePartEvent(sessionId, part);
      // permission.v2.asked/replied replace the deprecated permission.asked —
      // confirmed via the live OpenAPI spec, whose only non-deprecated reply
      // endpoint (`POST /permission/{requestID}/reply`) is the v2 one.
      case 'permission.v2.asked':
        if (sessionId == null) return null;
        final source = props['source'] as Map<String, dynamic>?;
        final permissionId = props['id'] as String?;
        // Only a tool-call permission (source.type == "tool") concerns the
        // Code tab's transcript — confirmed shape: {type, messageID, callID}.
        if (source == null || source['type'] != 'tool' || permissionId == null) {
          return null;
        }
        final callId = source['callID'] as String?;
        if (callId == null) return null;
        return OpencodePermissionEvent(sessionId, permissionId, callId);
      case 'session.idle':
        if (sessionId == null) return null;
        return OpencodeSessionIdleEvent(sessionId);
      case 'session.error':
        if (sessionId == null) return null;
        return OpencodeSessionErrorEvent(sessionId, _errorMessage(props['error']));
      default:
        return null;
    }
  }

  static String _errorMessage(Object? error) {
    if (error is Map<String, dynamic>) {
      final data = error['data'];
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
      if (error['name'] is String) return error['name'] as String;
    }
    return 'Unknown error';
  }
}

/// A message part was created or changed — covers both assistant text
/// (`part['type'] == 'text'`, growing `part['text']`) and tool calls
/// (`part['type'] == 'tool'`, with `part['callID']`/`part['tool']`/
/// `part['state']`). Left as a raw JSON map rather than modeled further:
/// `CodeAgentController` is the only consumer and only needs a handful of
/// fields per type, so a second parsing layer here would just be overhead.
class OpencodePartEvent extends OpencodeEvent {
  const OpencodePartEvent(super.sessionId, this.part);
  final Map<String, dynamic> part;
}

/// A gated tool call (opencode's `edit`/`bash` permission rules — see
/// `opencode_process_supervisor.dart`'s generated config) is waiting on a
/// decision. [callId] matches the [OpencodePartEvent] tool part's `callID`,
/// which is how `CodeAgentController` finds the transcript row to mark
/// `awaitingApproval`.
class OpencodePermissionEvent extends OpencodeEvent {
  const OpencodePermissionEvent(super.sessionId, this.permissionId, this.callId);
  final String permissionId;
  final String callId;
}

/// The session finished processing the last message — everything opencode
/// is going to say or do for this turn has already arrived as prior events.
class OpencodeSessionIdleEvent extends OpencodeEvent {
  const OpencodeSessionIdleEvent(super.sessionId);
}

class OpencodeSessionErrorEvent extends OpencodeEvent {
  const OpencodeSessionErrorEvent(super.sessionId, this.message);
  final String message;
}

/// Talks to a running `opencode serve` process's HTTP API. Abstract so
/// `CodeAgentController` stays unit-testable without a real subprocess —
/// mirrors how `ProjectRootSource` is faked for the same reason. Every
/// method takes [projectRoot] because opencode scopes sessions, messages,
/// permissions, and events to it via a `directory` query parameter rather
/// than the server process's own cwd — confirmed against a running server,
/// not documented: a single `opencode serve` instance can host any number of
/// project directories at once, so `OpencodeProcessSupervisor` never needs
/// to restart it when the Code tab's project root changes.
abstract class OpencodeClient {
  /// Creates a session scoped to [projectRoot]. Returns opencode's session id.
  Future<String> createSession(String projectRoot);

  /// Sends [text] into [sessionId] and returns as soon as opencode has
  /// accepted it — the reply and any tool activity arrive as [events], not
  /// as this call's result (`POST .../prompt_async`, confirmed to return
  /// immediately rather than blocking for the whole turn like the plain
  /// `.../message` endpoint does).
  Future<void> sendMessageAsync({
    required String projectRoot,
    required String sessionId,
    required String providerId,
    required String modelId,
    required String text,
  });

  /// Approves or denies a pending permission request.
  Future<void> respondToPermission({
    required String projectRoot,
    required String permissionId,
    required ToolApprovalDecision decision,
  });

  /// Interrupts an in-flight turn — opencode's real equivalent of the old
  /// local agent loop's `pool.cancel()`. Called from `stop()`; best-effort,
  /// since the UI has already moved on regardless of whether this succeeds.
  Future<void> abort({required String projectRoot, required String sessionId});

  /// The directory-scoped event stream for [projectRoot] — reopen (call
  /// again) if the Code tab's project root changes; each call is an
  /// independent connection.
  Stream<OpencodeEvent> events(String projectRoot);

  Future<void> close();
}

class HttpOpencodeClient implements OpencodeClient {
  HttpOpencodeClient({
    required this.baseUrl,
    http.Client? httpClient,
    http.Client Function()? eventClientFactory,
  })  : _http = httpClient ?? http.Client(),
        _eventClientFactory = eventClientFactory ?? http.Client.new;

  /// e.g. `http://127.0.0.1:8101` — see `OpencodeProcessSupervisor.baseUrl`.
  final String baseUrl;
  final http.Client _http;

  /// Builds the dedicated client [events] uses — overridable so tests can
  /// substitute `MockClient.streaming` without a real socket.
  final http.Client Function() _eventClientFactory;

  Uri _uri(String path, String projectRoot) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: {'directory': projectRoot});

  void _checkOk(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'opencode: failed to $action (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<String> createSession(String projectRoot) async {
    final response = await _http.post(
      _uri('/session', projectRoot),
      headers: const {'Content-Type': 'application/json'},
      body: '{}',
    );
    _checkOk(response, 'create session');
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<void> sendMessageAsync({
    required String projectRoot,
    required String sessionId,
    required String providerId,
    required String modelId,
    required String text,
  }) async {
    final response = await _http.post(
      _uri('/session/$sessionId/prompt_async', projectRoot),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': {'providerID': providerId, 'modelID': modelId},
        'parts': [
          {'type': 'text', 'text': text},
        ],
      }),
    );
    _checkOk(response, 'send message');
  }

  @override
  Future<void> respondToPermission({
    required String projectRoot,
    required String permissionId,
    required ToolApprovalDecision decision,
  }) async {
    // once/always/reject — confirmed literal values against the live
    // OpenAPI spec's PermissionV2Reply enum.
    final reply = switch (decision) {
      ToolApprovalDecision.allowOnce => 'once',
      ToolApprovalDecision.allowForSession => 'always',
      ToolApprovalDecision.deny => 'reject',
    };
    final response = await _http.post(
      _uri('/permission/$permissionId/reply', projectRoot),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'reply': reply}),
    );
    _checkOk(response, 'respond to permission');
  }

  @override
  Future<void> abort({required String projectRoot, required String sessionId}) async {
    final response = await _http.post(_uri('/session/$sessionId/abort', projectRoot));
    _checkOk(response, 'abort session');
  }

  @override
  Stream<OpencodeEvent> events(String projectRoot) {
    late final StreamController<OpencodeEvent> controller;
    // A dedicated client (not the shared `_http`) so cancelling the stream
    // can force-close this one long-lived connection without affecting the
    // request/response calls above.
    final streamClient = _eventClientFactory();
    StreamSubscription<String>? sub;

    Future<void> start() async {
      try {
        final request = http.Request('GET', _uri('/event', projectRoot));
        final response = await streamClient.send(request);
        if (response.statusCode != 200) {
          controller.addError(StateError('opencode: /event returned ${response.statusCode}'));
          await controller.close();
          return;
        }
        // SSE frames are separated by a blank line; each frame may carry
        // several `field: value` lines but opencode's stream only uses
        // `data:`. Buffer across chunk boundaries since a frame can split
        // arbitrarily across TCP reads.
        var buffer = '';
        sub = response.stream.transform(utf8.decoder).listen(
          (chunk) {
            buffer += chunk;
            while (true) {
              final end = buffer.indexOf('\n\n');
              if (end == -1) break;
              final frame = buffer.substring(0, end);
              buffer = buffer.substring(end + 2);
              for (final line in const LineSplitter().convert(frame)) {
                if (!line.startsWith('data:')) continue;
                final payload = line.substring(5).trim();
                if (payload.isEmpty) continue;
                try {
                  final decoded = jsonDecode(payload) as Map<String, dynamic>;
                  final event = OpencodeEvent.tryParse(decoded);
                  if (event != null) controller.add(event);
                } on FormatException {
                  // Malformed line — drop it rather than kill the stream.
                }
              }
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }

    controller = StreamController<OpencodeEvent>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        await sub?.cancel();
        streamClient.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> close() async {
    _http.close();
  }
}
