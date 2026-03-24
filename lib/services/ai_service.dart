import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/message.dart';

class AiService {
  static const String _baseUrl = 'http://localhost:8080';
  static const String _chatEndpoint = '/v1/chat/completions';
  static const String _healthEndpoint = '/health';

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl$_healthEndpoint'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> sendMessage(List<Message> messages) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl$_chatEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'local',
            'messages': messages.map((m) => m.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No choices returned from server');
    }
    final content =
        choices[0]['message']['content'] as String;
    return content;
  }
}
