import 'dart:convert';

import 'package:http/http.dart' as http;

/// Backend host the app talks to. Relative paths like `/api/hello` only
/// resolve in a browser; native builds need an absolute origin.
const String apiBaseUrl = 'http://localhost:8000';

class ModelInfo {
  const ModelInfo({required this.id, required this.name, this.gguf});

  final String id;
  final String name;

  /// llama.cpp model source (e.g. `hf://owner/repo/file.gguf`). When set,
  /// the app runs this model on-device instead of calling the server.
  final String? gguf;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      gguf: json['gguf'] as String?,
    );
  }
}

class ApiClient {
  Future<List<ModelInfo>> fetchModels() async {
    final response = await http.get(Uri.parse('$apiBaseUrl/api/models'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = data['models'] as List<dynamic>;
    return models.map((m) => ModelInfo.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<String> sendChat({required String model, required String message}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model, 'message': message}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'request failed (${response.statusCode})');
    }
    return data['reply'] as String;
  }
}
