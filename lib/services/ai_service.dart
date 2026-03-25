import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/message.dart';

/// Represents the response from a chat completion request.
///
/// Either [text] is set (plain assistant reply) or [toolCalls] is set
/// (the model wants to call one or more tools before answering).
class ChatResponse {
  final String? text;
  final List<ToolCall>? toolCalls;

  const ChatResponse.text(String this.text) : toolCalls = null;
  const ChatResponse.tools(List<ToolCall> this.toolCalls) : text = null;

  bool get isToolCall => toolCalls != null && toolCalls!.isNotEmpty;
}

/// A single tool invocation requested by the model.
class ToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  const ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });
}

class AiService {
  static const String _baseUrl = 'http://localhost:8080';
  static const String _chatEndpoint = '/v1/chat/completions';
  static const String _healthEndpoint = '/health';
  static const String _stopEndpoint = '/stop';

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

  /// Sends a chat completion request.
  ///
  /// [tools] is an optional list of tool schemas (from [ToolService.toolSchemas]).
  /// Returns a [ChatResponse] that is either plain text or a tool-call request.
  Future<ChatResponse> sendMessage(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final body = <String, dynamic>{
      'model': 'local',
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl$_chatEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
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

    final message = choices[0]['message'] as Map<String, dynamic>;
    final rawToolCalls = message['tool_calls'] as List<dynamic>?;

    if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
      final toolCalls = rawToolCalls.map((tc) {
        final tcMap = tc as Map<String, dynamic>;
        final fn = tcMap['function'] as Map<String, dynamic>;
        return ToolCall(
          id: tcMap['id'] as String? ?? '',
          name: fn['name'] as String? ?? '',
          argumentsJson: fn['arguments'] as String? ?? '{}',
        );
      }).toList();
      return ChatResponse.tools(toolCalls);
    }

    final content = message['content'] as String? ?? '';
    return ChatResponse.text(content);
  }

  Future<void> stopServer() async {
    try {
      await http
          .get(Uri.parse('$_baseUrl$_stopEndpoint'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore errors — server may close the connection before responding.
    }
  }
}
