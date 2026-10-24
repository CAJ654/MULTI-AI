import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../chat_types.dart' show ChatTurn;

/// Runs [prompt] past the model named [modelId] and returns its whole reply.
/// `ModelPool.generate` adapted to ids, so the server can be tested without a
/// pool.
typedef GenerateReply = Future<String> Function(
  String modelId,
  String prompt,
  List<ChatTurn> history,
);

/// One request the server handled, for the add-on's activity log.
class ServerRequestLog {
  const ServerRequestLog({
    required this.method,
    required this.path,
    required this.status,
    required this.duration,
    this.modelId,
  });

  final String method;
  final String path;
  final int status;
  final Duration duration;

  /// Null for requests that never reached a model (auth failures, /models).
  final String? modelId;
}

/// A minimal OpenAI-compatible HTTP server over the app's models, so a
/// community proxy in front of Google Antigravity can use them. Antigravity
/// itself has no supported custom-provider setting — see the README section on
/// the add-on — so this only guarantees a correct endpoint, not the other end.
///
/// Serves `GET /v1/models` and `POST /v1/chat/completions` (the `/v1` prefix is
/// optional). Deliberately narrow:
/// - **No tool calling.** `tools`/`tool_choice` are ignored and the reply is
///   plain text, because `ModelPool.generate` has none to offer.
/// - **Streaming is faked.** `ModelPool.generate` returns the whole reply, so
///   `stream: true` sends one content chunk once it's ready, with SSE comment
///   keep-alives while waiting so a client doesn't time out on a slow model.
///
/// Binds loopback only, requires `Authorization: Bearer <token>`, and refuses
/// any request that carries an `Origin` header or a non-loopback `Host` — the
/// first stops a web page in the user's browser from POSTing to it, the second
/// stops DNS rebinding from getting around that.
class LocalModelServer {
  LocalModelServer({
    required this.generate,
    required this.models,
    required this.defaultModel,
    required this.token,
    this.cancel,
    this.onRequest,
    this.maxBodyBytes = 4 * 1024 * 1024,
    this.keepAliveInterval = const Duration(seconds: 10),
  });

  final GenerateReply generate;

  /// Ids of the models that can be served right now (`ModelPool.downloaded`).
  final List<String> Function() models;

  /// The model used when a request names one that isn't in [models] — a proxy
  /// forwards whatever model name Antigravity asked for, e.g. a Gemini one.
  final String? Function() defaultModel;

  /// Read per request, so regenerating the token takes effect without a
  /// restart.
  final String Function() token;

  /// Aborts the generation in flight when a client disconnects. Only called
  /// when that generation is the server's only one, since `ModelPool.cancel`
  /// can't say which request it stops. Only streamed requests are noticed:
  /// dart:io sees a closed socket when it writes to it, and a non-streamed
  /// request writes nothing until the reply is ready.
  final void Function()? cancel;

  final void Function(ServerRequestLog log)? onRequest;

  final int maxBodyBytes;
  final Duration keepAliveInterval;

  HttpServer? _server;
  int _inFlight = 0;

  bool get running => _server != null;

  /// The port actually bound — differs from the one asked for only when that
  /// was 0 (tests).
  int? get port => _server?.port;

  /// Starts listening and returns the bound port. A no-op if already running;
  /// throws a [SocketException] if the port is taken.
  Future<int> start(int port) async {
    final existing = _server;
    if (existing != null) {
      return existing.port;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final started = DateTime.now();
    final outcome = _Outcome();
    try {
      await _dispatch(request, outcome);
    } catch (e) {
      if (outcome.streaming) {
        // Headers are gone; all that's left is to end the stream.
        _tryWrite(request.response, 'data: ${jsonEncode(_errorBody('server_error', '$e'))}\n\ndata: [DONE]\n\n');
      } else {
        outcome.status = 500;
        _writeJson(request.response, 500, _errorBody('server_error', 'Internal error: $e'));
      }
    } finally {
      try {
        await request.response.close();
      } catch (_) {
        // The client already went away.
      }
      onRequest?.call(ServerRequestLog(
        method: request.method,
        path: request.uri.path,
        status: outcome.status,
        modelId: outcome.modelId,
        duration: DateTime.now().difference(started),
      ));
    }
  }

  Future<void> _dispatch(HttpRequest request, _Outcome outcome) async {
    final response = request.response;
    if (!_hostAllowed(request) || request.headers.value('origin') != null) {
      outcome.status = 403;
      _writeJson(response, 403, _errorBody('forbidden', 'Only direct loopback requests are accepted.'));
      return;
    }
    if (!_authorized(request)) {
      outcome.status = 401;
      response.headers.set('www-authenticate', 'Bearer');
      _writeJson(response, 401, _errorBody('invalid_api_key', 'Missing or wrong bearer token.'));
      return;
    }
    final path = request.uri.path;
    final route = path.startsWith('/v1/') ? path.substring(3) : path;
    if (request.method == 'GET' && route == '/models') {
      outcome.status = 200;
      _writeJson(response, 200, {
        'object': 'list',
        'data': [
          for (final id in models()) {'id': id, 'object': 'model', 'created': 0, 'owned_by': 'multi-ai'},
        ],
      });
      return;
    }
    if (request.method == 'POST' && route == '/chat/completions') {
      await _chatCompletions(request, outcome);
      return;
    }
    outcome.status = 404;
    _writeJson(response, 404, _errorBody('not_found', 'No such endpoint: ${request.method} $path'));
  }

  Future<void> _chatCompletions(HttpRequest request, _Outcome outcome) async {
    final response = request.response;
    final bytes = await _readBody(request);
    if (bytes == null) {
      outcome.status = 413;
      response.headers.set('connection', 'close');
      _writeJson(response, 413, _errorBody('request_too_large', 'Request body is over the $maxBodyBytes byte limit.'));
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      decoded = null;
    }
    final rawMessages = decoded is Map ? decoded['messages'] : null;
    final parsed = rawMessages is List ? _parseMessages(rawMessages) : null;
    if (decoded is! Map || parsed == null) {
      outcome.status = 400;
      _writeJson(
        response,
        400,
        _errorBody('invalid_request_error',
            'Expected a JSON body with a "messages" array that ends in a user message.'),
      );
      return;
    }
    final modelId = _resolveModel(decoded['model']);
    if (modelId == null) {
      outcome.status = 503;
      _writeJson(response, 503, _errorBody('model_not_available', 'No downloaded model is available to serve.'));
      return;
    }
    outcome.modelId = modelId;
    final stream = decoded['stream'] == true;
    final completionId = 'chatcmpl-${_randomId()}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _inFlight++;
    var settled = false;
    // Best-effort: this handler doesn't close the response until the reply is
    // ready, so `done` completing before then — with an error or without —
    // means the client hung up mid-generation.
    void onClientGone() {
      if (!settled && _inFlight == 1) {
        cancel?.call();
      }
    }

    unawaited(response.done.then<void>((_) => onClientGone(), onError: (_) => onClientGone()));
    Timer? keepAlive;
    try {
      if (stream) {
        outcome.streaming = true;
        outcome.status = 200;
        response.statusCode = 200;
        response.bufferOutput = false;
        response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
        response.headers.set('cache-control', 'no-cache');
        _tryWrite(response, _sseChunk(completionId, created, modelId, {'role': 'assistant'}, null));
        keepAlive = Timer.periodic(keepAliveInterval, (_) => _tryWrite(response, ': keep-alive\n\n'));
      }
      final reply = await generate(modelId, parsed.prompt, parsed.history);
      settled = true;
      keepAlive?.cancel();
      if (stream) {
        _tryWrite(response, _sseChunk(completionId, created, modelId, {'content': reply}, null));
        _tryWrite(response, _sseChunk(completionId, created, modelId, const {}, 'stop'));
        _tryWrite(response, 'data: [DONE]\n\n');
      } else {
        outcome.status = 200;
        final promptTokens = _estimateTokens(parsed.prompt) +
            parsed.history.fold<int>(0, (sum, t) => sum + _estimateTokens(t.text));
        final completionTokens = _estimateTokens(reply);
        _writeJson(response, 200, {
          'id': completionId,
          'object': 'chat.completion',
          'created': created,
          'model': modelId,
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': reply},
              'finish_reason': 'stop',
            },
          ],
          // Rough (chars / 4) — the pool doesn't report real token counts.
          'usage': {
            'prompt_tokens': promptTokens,
            'completion_tokens': completionTokens,
            'total_tokens': promptTokens + completionTokens,
          },
        });
      }
    } catch (e) {
      settled = true;
      if (stream) {
        outcome.status = 500;
        _tryWrite(response, 'data: ${jsonEncode(_errorBody('generation_failed', '$e'))}\n\ndata: [DONE]\n\n');
      } else {
        outcome.status = 500;
        _writeJson(response, 500, _errorBody('generation_failed', '$e'));
      }
    } finally {
      keepAlive?.cancel();
      _inFlight--;
    }
  }

  /// The model to run for a request naming [requested]: that one if it can be
  /// served, otherwise the configured default, otherwise the first available.
  String? _resolveModel(Object? requested) {
    final available = models();
    if (requested is String && available.contains(requested)) {
      return requested;
    }
    final fallback = defaultModel();
    if (fallback != null && available.contains(fallback)) {
      return fallback;
    }
    return available.isEmpty ? null : available.first;
  }

  bool _hostAllowed(HttpRequest request) {
    final host = request.headers.host;
    return host == '127.0.0.1' || host == 'localhost' || host == '[::1]' || host == '::1';
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      return false;
    }
    return _constantTimeEquals(header.substring(7).trim(), token());
  }

  /// The whole body, or null if it runs past [maxBodyBytes].
  Future<List<int>?> _readBody(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) {
        return null;
      }
    }
    return bytes;
  }
}

/// What a request ended up as, filled in by the handlers for the log and so
/// [LocalModelServer._handle] knows whether headers are already out.
class _Outcome {
  int status = 500;
  String? modelId;
  bool streaming = false;
}

/// Splits OpenAI `messages` into the pool's shape: the final user message
/// becomes the prompt (with any system messages prepended, since [ChatTurn]
/// has no system role) and everything before it the history. Null when the
/// conversation doesn't end on a user turn, so there's nothing to answer.
({String prompt, List<ChatTurn> history})? _parseMessages(List<dynamic> messages) {
  final system = <String>[];
  final turns = <ChatTurn>[];
  for (final message in messages) {
    if (message is! Map) {
      continue;
    }
    final text = _contentText(message['content']);
    if (text.isEmpty) {
      continue;
    }
    switch (message['role']) {
      case 'system' || 'developer':
        system.add(text);
      case 'assistant':
        turns.add(ChatTurn(isUser: false, text: text));
      case 'tool' || 'function':
        turns.add(ChatTurn(isUser: true, text: 'Tool result:\n$text'));
      default:
        turns.add(ChatTurn(isUser: true, text: text));
    }
  }
  if (turns.isEmpty || !turns.last.isUser) {
    return null;
  }
  final last = turns.removeLast();
  final prompt = system.isEmpty ? last.text : '${system.join('\n\n')}\n\n${last.text}';
  return (prompt: prompt, history: turns);
}

/// A message's text whether `content` is a plain string or the newer list of
/// typed parts; non-text parts (images) are dropped.
String _contentText(Object? content) {
  if (content is String) {
    return content;
  }
  if (content is List) {
    return content
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join('\n');
  }
  return '';
}

int _estimateTokens(String text) => (text.length / 4).ceil();

Map<String, dynamic> _errorBody(String type, String message) => {
      'error': {'message': message, 'type': type},
    };

String _sseChunk(
  String id,
  int created,
  String model,
  Map<String, dynamic> delta,
  String? finishReason,
) {
  final chunk = {
    'id': id,
    'object': 'chat.completion.chunk',
    'created': created,
    'model': model,
    'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': finishReason},
    ],
  };
  return 'data: ${jsonEncode(chunk)}\n\n';
}

void _writeJson(HttpResponse response, int status, Object body) {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
}

/// Writes to a response the client may have already closed; a failed write
/// there is expected, not an error.
void _tryWrite(HttpResponse response, String text) {
  try {
    response.write(text);
  } catch (_) {
    // Client disconnected.
  }
}

bool _constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

String _randomId() {
  final random = Random.secure();
  return List.generate(12, (_) => random.nextInt(36).toRadixString(36)).join();
}
