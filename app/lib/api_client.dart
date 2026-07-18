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
    this.gguf,
    this.params,
    this.sizeGb,
    this.modality,
    this.contextTokens,
    this.license,
    this.strengths,
    this.speedProfile,
  });

  final String id;
  final String name;

  /// llama.cpp model source (e.g. `hf://owner/repo/file.gguf`). When set,
  /// the app runs this model on-device instead of calling the server.
  final String? gguf;

  /// Parameter count as a human label (e.g. `"7B"`, `"124M"`), for the
  /// Models tab. Null for entries the backend hasn't annotated.
  final String? params;

  /// Approximate download size in GB, for the Models tab. Null for entries
  /// the backend hasn't annotated.
  final double? sizeGb;

  /// What kinds of input the checkpoint accepts (e.g. `"Text"`,
  /// `"Text + Image"`). Null for entries the backend hasn't annotated.
  final String? modality;

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
      gguf: json['gguf'] as String?,
      params: json['params'] as String?,
      sizeGb: (json['size_gb'] as num?)?.toDouble(),
      modality: json['modality'] as String?,
      contextTokens: (json['context_tokens'] as num?)?.toInt(),
      license: json['license'] as String?,
      strengths: json['strengths'] as String?,
      speedProfile: json['speed_profile'] as String?,
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

  Future<String> sendChat({required String model, required String message}) async {
    // A dedicated client per chat request so cancelChat can abort it without
    // touching anything else.
    final client = http.Client();
    _chatClient = client;
    try {
      final response = await client.post(
        Uri.parse('$apiBaseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'message': message}),
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
