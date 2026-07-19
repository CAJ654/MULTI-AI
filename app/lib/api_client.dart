import 'dart:convert';

// defaultTargetPlatform rather than dart:io's Platform: this file is also
// compiled for web, where importing dart:io fails outright.
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;

/// Backend host the app talks to. Relative paths like `/api/hello` only
/// resolve in a browser; native builds need an absolute origin.
///
/// Defaults are per-platform because "localhost" means different machines on
/// different targets. Override for a physical device — whose backend lives on
/// the LAN, not on the phone — with:
///
///     flutter run --dart-define=MULTI_AI_API_BASE_URL=http://192.168.1.x:8000
///
/// (a LAN IP also needs adding to `network_security_config.xml`, since the
/// backend is cleartext HTTP).
final String apiBaseUrl = () {
  const override = String.fromEnvironment('MULTI_AI_API_BASE_URL');
  if (override.isNotEmpty) return override;
  // 10.0.2.2 is the Android emulator's alias for the host machine's loopback;
  // plain localhost there resolves to the emulated device itself.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}();

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    this.available = true,
    this.gguf,
    this.mmproj,
    this.params,
    this.sizeGb,
    this.modality,
    this.inputModalities = const ['text'],
    this.contextTokens,
    this.license,
    this.strengths,
    this.speedProfile,
  });

  final String id;
  final String name;

  /// Whether this entry actually declares a `_REPO_ID` or `_GGUF_SOURCE` —
  /// false for stub/broken model files, which can't run or manage weights.
  final bool available;

  /// llama.cpp model source (e.g. `hf://owner/repo/file.gguf`). When set,
  /// the app runs this model on-device instead of calling the server.
  final String? gguf;

  /// Companion multimodal-projector source for a vision [gguf]. llama.cpp
  /// encodes images through this separate file, so on-device image input
  /// needs both downloaded — see [OnDeviceEngine.generate].
  final String? mmproj;

  /// Parameter count as a human label (e.g. `"7B"`, `"124M"`), for the
  /// Models tab. Null for entries the backend hasn't annotated.
  final String? params;

  /// Approximate download size in GB, for the Models tab. Null for entries
  /// the backend hasn't annotated.
  final double? sizeGb;

  /// What kinds of input the checkpoint accepts (e.g. `"Text"`,
  /// `"Text + Image"`). Null for entries the backend hasn't annotated.
  ///
  /// Prose, for the Models tab only — [inputModalities] is the machine-
  /// readable version the chat input actually gates on.
  final String? modality;

  /// Input kinds this model accepts, as backend-declared tokens: always
  /// `'text'`, plus `'image'` and/or `'audio'` for multimodal checkpoints.
  /// Gates the chat input's attach (+) and mic buttons.
  final List<String> inputModalities;

  bool get acceptsImages => inputModalities.contains('image');
  bool get acceptsAudio => inputModalities.contains('audio');

  /// Human-readable modality label, derived from [inputModalities] rather
  /// than the prose [modality] field.
  ///
  /// The two used to be able to disagree: an on-device GGUF sibling inherits
  /// its `modality` string from the checkpoint it mirrors ("Text + Image +
  /// Audio" for Gemma 3n), but llama.cpp only runs its text path — so the
  /// Models tab advertised image input the chat input then refused to offer.
  /// Deriving both from one field keeps that from drifting apart again.
  String get modalityLabel => [
        for (final m in inputModalities)
          if (m.isNotEmpty) '${m[0].toUpperCase()}${m.substring(1)}',
      ].join(' + ');

  /// Trained/native context window in tokens. Null for entries the backend
  /// hasn't annotated.
  final int? contextTokens;

  /// Open-source (or custom-permissive) license name. Null for entries the
  /// backend hasn't annotated.
  final String? license;

  /// Short editorial blurb on what the model is good at. Null for entries
  /// the backend hasn't annotated.
  final String? strengths;

  /// Short qualitative intelligence-vs-speed tradeoff (e.g. `"Slow, deep
  /// reasoning"`). Null for entries the backend hasn't annotated.
  final String? speedProfile;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      available: json['available'] as bool? ?? true,
      gguf: json['gguf'] as String?,
      mmproj: json['mmproj'] as String?,
      params: json['params'] as String?,
      sizeGb: (json['size_gb'] as num?)?.toDouble(),
      modality: json['modality'] as String?,
      // An older backend omits this; text-only is the safe assumption.
      inputModalities:
          (json['input_modalities'] as List<dynamic>?)?.cast<String>() ?? const ['text'],
      contextTokens: (json['context_tokens'] as num?)?.toInt(),
      license: json['license'] as String?,
      strengths: json['strengths'] as String?,
      speedProfile: json['speed_profile'] as String?,
    );
  }
}

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

/// Disk-cache state of a server-backed (`_REPO_ID`) model's weights, as
/// reported by the Python backend's Hugging Face cache.
class ServerModelCacheStatus {
  const ServerModelCacheStatus({required this.cached, this.sizeBytes});

  final bool cached;
  final int? sizeBytes;

  factory ServerModelCacheStatus.fromJson(Map<String, dynamic> json) {
    return ServerModelCacheStatus(
      cached: json['cached'] as bool,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
    );
  }
}

class ApiClient {
  http.Client? _chatClient;

  Future<List<ModelInfo>> fetchModels() async {
    final response = await http.get(Uri.parse('$apiBaseUrl/api/models'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = data['models'] as List<dynamic>;
    return models.map((m) => ModelInfo.fromJson(m as Map<String, dynamic>)).toList();
  }

  /// Whether a server-backed model's weights are already in the backend
  /// machine's Hugging Face cache.
  Future<ServerModelCacheStatus> getServerModelCacheStatus(String modelId) async {
    final response = await http.get(Uri.parse('$apiBaseUrl/api/models/$modelId/cache'));
    return _decodeCacheStatus(response);
  }

  /// Downloads (and warms up) a server-backed model's weights. Blocks until
  /// the backend finishes fetching them — can take a while for large models.
  Future<ServerModelCacheStatus> downloadServerModel(String modelId) async {
    final response = await http.post(Uri.parse('$apiBaseUrl/api/models/$modelId/download'));
    return _decodeCacheStatus(response);
  }

  /// Deletes a server-backed model's cached weights from the backend
  /// machine's disk (and evicts it from memory if resident).
  Future<ServerModelCacheStatus> deleteServerModel(String modelId) async {
    final response = await http.delete(Uri.parse('$apiBaseUrl/api/models/$modelId/cache'));
    return _decodeCacheStatus(response);
  }

  ServerModelCacheStatus _decodeCacheStatus(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'request failed (${response.statusCode})');
    }
    return ServerModelCacheStatus.fromJson(data);
  }

  Future<String> sendChat({
    required String model,
    required String message,
    List<Attachment> attachments = const [],
  }) async {
    // A dedicated client per chat request so cancelChat can abort it without
    // touching anything else.
    final client = http.Client();
    _chatClient = client;
    try {
      final response = await client.post(
        Uri.parse('$apiBaseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'message': message,
          if (attachments.isNotEmpty)
            'attachments': [for (final a in attachments) a.toWireJson()],
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'request failed (${response.statusCode})');
      }
      return data['reply'] as String;
    } finally {
      if (identical(_chatClient, client)) _chatClient = null;
      client.close();
    }
  }

  /// Aborts the in-flight chat request, if any. The server still finishes
  /// generating on its side; the response just never reaches us.
  void cancelChat() {
    _chatClient?.close();
    _chatClient = null;
  }
}
