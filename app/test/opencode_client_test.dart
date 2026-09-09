import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:multi_ai/addons/code/opencode_client.dart';
import 'package:multi_ai/addons/code/tool_approval.dart';

void main() {
  group('HttpOpencodeClient requests', () {
    test('createSession posts to /session?directory= and returns the id', () async {
      late http.Request captured;
      final client = HttpOpencodeClient(
        baseUrl: 'http://127.0.0.1:8101',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'id': 'ses_abc'}), 200);
        }),
      );

      final id = await client.createSession('C:/projects/demo');

      expect(id, 'ses_abc');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/session');
      expect(captured.url.queryParameters['directory'], 'C:/projects/demo');
    });

    test('sendMessageAsync sends the {providerID, modelID} model shape and a text part', () async {
      late http.Request captured;
      final client = HttpOpencodeClient(
        baseUrl: 'http://127.0.0.1:8101',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );

      await client.sendMessageAsync(
        projectRoot: 'C:/projects/demo',
        sessionId: 'ses_abc',
        providerId: 'multiai-local',
        modelId: 'local',
        text: 'list the files',
      );

      expect(captured.url.path, '/session/ses_abc/prompt_async');
      expect(captured.url.queryParameters['directory'], 'C:/projects/demo');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], {'providerID': 'multiai-local', 'modelID': 'local'});
      expect(body['parts'], [
        {'type': 'text', 'text': 'list the files'},
      ]);
    });

    test('respondToPermission maps each decision to the reply opencode expects', () async {
      final bodies = <String>[];
      final client = HttpOpencodeClient(
        baseUrl: 'http://127.0.0.1:8101',
        httpClient: MockClient((request) async {
          bodies.add(request.body);
          return http.Response('true', 200);
        }),
      );

      for (final decision in ToolApprovalDecision.values) {
        await client.respondToPermission(
          projectRoot: 'C:/projects/demo',
          permissionId: 'per_1',
          decision: decision,
        );
      }

      expect(
        bodies.map((b) => (jsonDecode(b) as Map<String, dynamic>)['reply']),
        ['once', 'always', 'reject'],
      );
    });

    test('a non-2xx response throws with the status code and body', () async {
      final client = HttpOpencodeClient(
        baseUrl: 'http://127.0.0.1:8101',
        httpClient: MockClient((request) async => http.Response('bad request', 400)),
      );

      expect(
        () => client.createSession('C:/projects/demo'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('400'))),
      );
    });
  });

  group('HttpOpencodeClient.events SSE parsing', () {
    Stream<List<int>> chunks(List<String> parts) =>
        Stream.fromIterable(parts.map(utf8.encode));

    HttpOpencodeClient clientStreaming(List<String> chunkStrings) {
      return HttpOpencodeClient(
        baseUrl: 'http://127.0.0.1:8101',
        eventClientFactory: () => MockClient.streaming((request, _) async {
          return http.StreamedResponse(chunks(chunkStrings), 200);
        }),
      );
    }

    test('decodes a session.idle event delivered as one frame', () async {
      final client = clientStreaming([
        'data: ${jsonEncode({
              'id': 'evt_1',
              'type': 'session.idle',
              'properties': {'sessionID': 'ses_x'},
            })}\n\n',
      ]);

      final event = await client.events('C:/projects/demo').first;
      expect(event, isA<OpencodeSessionIdleEvent>());
      expect(event.sessionId, 'ses_x');
    });

    test('reassembles one SSE frame split arbitrarily across chunk boundaries', () async {
      final payload = jsonEncode({
        'id': 'evt_2',
        'type': 'session.error',
        'properties': {
          'sessionID': 'ses_x',
          'error': {
            'name': 'APIError',
            'data': {'message': 'Cannot connect to API'},
          },
        },
      });
      // Split mid-JSON, and mid the trailing blank-line frame terminator.
      final full = 'data: $payload\n\n';
      final splitPoint = full.length ~/ 2;
      final client = clientStreaming([
        full.substring(0, splitPoint),
        full.substring(splitPoint),
      ]);

      final event = await client.events('C:/projects/demo').first as OpencodeSessionErrorEvent;
      expect(event.sessionId, 'ses_x');
      expect(event.message, 'Cannot connect to API');
    });

    test('a tool permission event only fires for source.type == tool', () async {
      final toolAsk = jsonEncode({
        'id': 'evt_3',
        'type': 'permission.v2.asked',
        'properties': {
          'id': 'per_1',
          'sessionID': 'ses_x',
          'action': 'edit',
          'resources': ['out.txt'],
          'source': {'type': 'tool', 'messageID': 'msg_1', 'callID': 'call_1'},
        },
      });
      final nonToolAsk = jsonEncode({
        'id': 'evt_4',
        'type': 'permission.v2.asked',
        'properties': {
          'id': 'per_2',
          'sessionID': 'ses_x',
          'action': 'question',
          'resources': <String>[],
          'source': {'type': 'other'},
        },
      });
      final client = clientStreaming(['data: $nonToolAsk\n\ndata: $toolAsk\n\n']);

      final event = await client.events('C:/projects/demo').first as OpencodePermissionEvent;
      expect(event.permissionId, 'per_1');
      expect(event.callId, 'call_1');
    });

    test('an unknown event type and a malformed line are both dropped without killing the stream',
        () async {
      final known = jsonEncode({
        'id': 'evt_5',
        'type': 'session.idle',
        'properties': {'sessionID': 'ses_x'},
      });
      final client = clientStreaming([
        'data: {"type":"server.heartbeat","properties":{}}\n\n'
            'data: not json\n\n'
            'data: $known\n\n',
      ]);

      final events = await client.events('C:/projects/demo').toList();
      expect(events, hasLength(1));
      expect(events.single, isA<OpencodeSessionIdleEvent>());
    });

    test('a part event carries the raw part map through untouched', () async {
      final part = {
        'id': 'prt_1',
        'sessionID': 'ses_x',
        'messageID': 'msg_1',
        'type': 'text',
        'text': 'Found some files.',
      };
      final client = clientStreaming([
        'data: ${jsonEncode({
              'id': 'evt_6',
              'type': 'message.part.updated',
              'properties': {'sessionID': 'ses_x', 'part': part, 'time': 1},
            })}\n\n',
      ]);

      final event = await client.events('C:/projects/demo').first as OpencodePartEvent;
      expect(event.part, part);
    });
  });
}
