import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/antigravity/local_model_server.dart';
import 'package:multi_ai/chat_types.dart';

const _token = 'test-token';

void main() {
  late LocalModelServer server;
  late String base;
  late List<ServerRequestLog> logs;
  late List<({String model, String prompt, List<ChatTurn> history})> calls;
  var reply = 'hello back';
  Completer<String>? gate;
  var cancelled = 0;

  Future<void> boot({int maxBodyBytes = 4 * 1024 * 1024}) async {
    logs = [];
    calls = [];
    cancelled = 0;
    server = LocalModelServer(
      models: () => ['alpha', 'beta'],
      defaultModel: () => 'beta',
      token: () => _token,
      maxBodyBytes: maxBodyBytes,
      keepAliveInterval: const Duration(milliseconds: 50),
      onRequest: logs.add,
      cancel: () => cancelled++,
      generate: (model, prompt, history) async {
        calls.add((model: model, prompt: prompt, history: history));
        if (gate != null) {
          return gate!.future;
        }
        return reply;
      },
    );
    base = 'http://127.0.0.1:${await server.start(0)}';
  }

  setUp(() {
    reply = 'hello back';
    gate = null;
  });

  tearDown(() async {
    await server.stop();
  });

  Future<HttpClientResponse> send(
    String method,
    String path, {
    Object? body,
    String? token = _token,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.openUrl(method, Uri.parse('$base$path'));
    if (token != null) {
      request.headers.set('authorization', 'Bearer $token');
    }
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body is String ? body : jsonEncode(body));
    }
    return request.close();
  }

  Future<Map<String, dynamic>> json(HttpClientResponse r) async =>
      jsonDecode(await r.transform(utf8.decoder).join()) as Map<String, dynamic>;

  Map<String, dynamic> chat(List<Map<String, dynamic>> messages, {String? model, bool stream = false}) => {
        'model': model,
        'messages': messages,
        'stream': stream,
      };

  group('auth and hardening', () {
    setUp(boot);

    test('rejects a missing or wrong token', () async {
      expect((await send('GET', '/v1/models', token: null)).statusCode, 401);
      expect((await send('GET', '/v1/models', token: 'nope')).statusCode, 401);
      expect((await send('GET', '/v1/models')).statusCode, 200);
    });

    test('rejects any request carrying an Origin header', () async {
      final r = await send('GET', '/v1/models', headers: {'origin': 'http://evil.example'});
      expect(r.statusCode, 403);
    });

    test('rejects a non-loopback Host header', () async {
      final r = await send('GET', '/v1/models', headers: {'host': 'evil.example'});
      expect(r.statusCode, 403);
    });

    test('404s unknown endpoints', () async {
      expect((await send('GET', '/v1/nope')).statusCode, 404);
    });

    test('logs requests', () async {
      await (await send('GET', '/v1/models')).drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(logs.single.status, 200);
      expect(logs.single.path, '/v1/models');
    });
  });

  group('models', () {
    setUp(boot);

    test('lists served models, with or without the /v1 prefix', () async {
      for (final path in ['/v1/models', '/models']) {
        final body = await json(await send('GET', path));
        expect([for (final m in body['data'] as List) (m as Map)['id']], ['alpha', 'beta']);
      }
    });
  });

  group('chat completions', () {
    setUp(boot);

    test('returns an OpenAI chat.completion', () async {
      final r = await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ], model: 'alpha'));
      expect(r.statusCode, 200);
      final body = await json(r);
      expect(body['object'], 'chat.completion');
      expect(body['model'], 'alpha');
      final choice = (body['choices'] as List).single as Map;
      expect((choice['message'] as Map)['content'], 'hello back');
      expect(choice['finish_reason'], 'stop');
      expect(calls.single.model, 'alpha');
      expect(calls.single.prompt, 'hi');
    });

    test('falls back to the default model for names it does not have', () async {
      await (await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ], model: 'gemini-3-pro'))).drain<void>();
      expect(calls.single.model, 'beta');
    });

    test('maps the last user message to the prompt, earlier ones to history, system prepended', () async {
      await (await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'first'},
        {'role': 'assistant', 'content': 'reply'},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'second'},
            {'type': 'image_url', 'image_url': {'url': 'x'}},
          ],
        },
      ]))).drain<void>();
      final call = calls.single;
      expect(call.prompt, 'Be brief.\n\nsecond');
      expect([for (final t in call.history) (t.isUser, t.text)], [(true, 'first'), (false, 'reply')]);
    });

    test('streams SSE chunks ending in [DONE]', () async {
      final r = await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ], stream: true));
      expect(r.statusCode, 200);
      expect(r.headers.contentType?.mimeType, 'text/event-stream');
      final text = await r.transform(utf8.decoder).join();
      final events = [
        for (final line in text.split('\n'))
          if (line.startsWith('data: ')) line.substring(6),
      ];
      expect(events.last, '[DONE]');
      final chunks = [for (final e in events.where((e) => e != '[DONE]')) jsonDecode(e) as Map];
      final content = chunks
          .map((c) => ((c['choices'] as List).single as Map)['delta'] as Map)
          .map((d) => d['content'])
          .whereType<String>()
          .join();
      expect(content, 'hello back');
      expect(((chunks.last['choices'] as List).single as Map)['finish_reason'], 'stop');
    });

    test('sends keep-alive comments while a streamed reply is pending', () async {
      gate = Completer<String>();
      final r = await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ], stream: true));
      final text = StringBuffer();
      final sub = r.transform(utf8.decoder).listen(text.write);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(text.toString(), contains(': keep-alive'));
      gate!.complete('done');
      await sub.asFuture<void>();
      expect(text.toString(), contains('done'));
    });

    test('rejects malformed JSON and conversations with nothing to answer', () async {
      expect((await send('POST', '/v1/chat/completions', body: '{not json')).statusCode, 400);
      expect((await send('POST', '/v1/chat/completions', body: {'messages': []})).statusCode, 400);
      final endsOnAssistant = chat([
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
      expect((await send('POST', '/v1/chat/completions', body: endsOnAssistant)).statusCode, 400);
      expect(calls, isEmpty);
    });

    test('reports a generation failure as a 500 error body', () async {
      await server.stop();
      server = LocalModelServer(
        models: () => ['alpha'],
        defaultModel: () => null,
        token: () => _token,
        generate: (_, _, _) async => throw StateError('boom'),
      );
      base = 'http://127.0.0.1:${await server.start(0)}';
      final r = await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ]));
      expect(r.statusCode, 500);
      expect(((await json(r))['error'] as Map)['message'], contains('boom'));
    });

    test('503s when no model is available', () async {
      await server.stop();
      server = LocalModelServer(
        models: () => const [],
        defaultModel: () => null,
        token: () => _token,
        generate: (_, _, _) async => reply,
      );
      base = 'http://127.0.0.1:${await server.start(0)}';
      final r = await send('POST', '/v1/chat/completions', body: chat([
        {'role': 'user', 'content': 'hi'},
      ]));
      expect(r.statusCode, 503);
    });

    test('cancels a streamed generation when the client disconnects', () async {
      gate = Completer<String>();
      final socket = await Socket.connect('127.0.0.1', server.port!);
      // Streamed only: dart:io notices a closed socket when it writes, and a
      // non-streamed request writes nothing until the reply is ready.
      final payload = jsonEncode(chat([
        {'role': 'user', 'content': 'hi'},
      ], stream: true));
      socket.write('POST /v1/chat/completions HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Authorization: Bearer $_token\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: ${utf8.encode(payload).length}\r\n\r\n$payload');
      await socket.flush();
      while (calls.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      socket.destroy();
      for (var i = 0; i < 100 && cancelled == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(cancelled, 1);
      gate!.complete('late');
    });
  });

  group('body limit', () {
    setUp(() => boot(maxBodyBytes: 64));

    test('refuses a body over the limit without running the model', () async {
      // The server answers 413 before the client finishes writing, so the
      // client sometimes sees a reset connection instead of the response.
      try {
        final r = await send('POST', '/v1/chat/completions', body: chat([
          {'role': 'user', 'content': 'x' * 500},
        ]));
        expect(r.statusCode, 413);
      } on SocketException {
        // Reset mid-write: the refusal still happened.
      } on HttpException {
        // Same, surfaced as a closed connection.
      }
      expect(calls, isEmpty);
    });
  });
}
