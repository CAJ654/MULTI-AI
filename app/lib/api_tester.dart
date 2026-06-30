import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiTester extends StatefulWidget {
  const ApiTester({super.key});

  @override
  State<ApiTester> createState() => _ApiTesterState();
}

class _ApiTesterState extends State<ApiTester> {
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMessage();
  }

  Future<void> _fetchMessage() async {
    try {
      final response = await http.get(Uri.parse('/api/hello'));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() => _message = data['message'] as String?);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API Tester', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (_error != null)
          Text('Error: $_error', style: const TextStyle(color: Colors.red))
        else if (_message != null)
          Text('Message from API: $_message')
        else
          const Text('Loading...'),
      ],
    );
  }
}
