import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/message.dart';

/// Default system prompt prepended to every conversation turn.
const String kDefaultSystemPrompt = 'You are Qwen, a helpful AI assistant.';

// ---------------------------------------------------------------------------
// Streaming event types
// ---------------------------------------------------------------------------

/// Base class for events emitted by [AiService.streamMessage].
sealed class AiStreamEvent {}

/// A single text token delta from the model.
class AiTextToken extends AiStreamEvent {
  final String token;
  AiTextToken(this.token);
}

/// Emitted at the end of a stream when the model requests tool invocations.
class AiToolCallsEvent extends AiStreamEvent {
  final List<ToolCall> toolCalls;
  AiToolCallsEvent(this.toolCalls);
}

// ---------------------------------------------------------------------------
// Non-streaming response (kept for compatibility)
// ---------------------------------------------------------------------------

/// Represents the response from a non-streaming chat completion request.
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

// ---------------------------------------------------------------------------
// AiService
// ---------------------------------------------------------------------------

class AiService {
  /// Base URL of the llama-server instance (configurable via Settings).
  final String baseUrl;

  static const String _chatEndpoint = '/v1/chat/completions';
  static const String _healthEndpoint = '/health';
  static const String _stopEndpoint = '/stop';

  AiService({this.baseUrl = 'http://localhost:8080'});

  // -------------------------------------------------------------------------
  // Health / server control
  // -------------------------------------------------------------------------

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl$_healthEndpoint'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopServer() async {
    try {
      await http
          .get(Uri.parse('$baseUrl$_stopEndpoint'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore — server may close connection before responding.
    }
  }

  // -------------------------------------------------------------------------
  // Non-streaming (used internally for tool-call rounds)
  // -------------------------------------------------------------------------

  /// Sends a non-streaming chat completion request.
  ///
  /// [tools] is an optional list of tool schemas (from [ToolService.toolSchemas]).
  /// Returns a [ChatResponse] that is either plain text or a tool-call request.
  Future<ChatResponse> sendMessage(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 512,
    double topP = 1.0,
  }) async {
    final body = <String, dynamic>{
      'model': 'local',
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'top_p': topP,
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl$_chatEndpoint'),
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

  // -------------------------------------------------------------------------
  // Streaming
  // -------------------------------------------------------------------------

  /// Streams a chat completion via Server-Sent Events.
  ///
  /// Yields [AiTextToken] events as text tokens arrive.  When the model
  /// requests tool calls instead of producing text, a single
  /// [AiToolCallsEvent] is emitted at the end of the stream.
  Stream<AiStreamEvent> streamMessage(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 512,
    double topP = 1.0,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl$_chatEndpoint'));
      request.headers['Content-Type'] = 'application/json';

      final body = <String, dynamic>{
        'model': 'local',
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'top_p': topP,
      };
      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      request.body = jsonEncode(body);

      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Server returned ${streamedResponse.statusCode}: $errorBody',
        );
      }

      // Accumulate tool-call fragments keyed by tool-call index.
      final toolCallBuffers = <int, _ToolCallBuffer>{};

      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;

        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue; // Skip malformed SSE frames.
        }

        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;

        final choice = choices[0] as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>? ?? {};

        // Text token
        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield AiTextToken(content);
        }

        // Tool-call fragments
        final rawToolCalls = delta['tool_calls'] as List<dynamic>?;
        if (rawToolCalls != null) {
          for (final tc in rawToolCalls) {
            final tcMap = tc as Map<String, dynamic>;
            final index = tcMap['index'] as int? ?? 0;
            final buf = toolCallBuffers.putIfAbsent(
              index,
              _ToolCallBuffer.new,
            );
            if (tcMap['id'] != null) buf.id = tcMap['id'] as String;
            final fn = tcMap['function'] as Map<String, dynamic>?;
            if (fn != null) {
              if (fn['name'] != null) buf.name = fn['name'] as String;
              if (fn['arguments'] != null) {
                buf.arguments += fn['arguments'] as String;
              }
            }
          }
        }
      }

      // If tool calls were accumulated, emit them as a single event.
      if (toolCallBuffers.isNotEmpty) {
        final toolCalls = toolCallBuffers.values
            .map(
              (buf) => ToolCall(
                id: buf.id,
                name: buf.name,
                argumentsJson: buf.arguments,
              ),
            )
            .toList();
        yield AiToolCallsEvent(toolCalls);
      }
    } on SocketException catch (e) {
      throw Exception('Network error: ${e.message}');
    } finally {
      client.close();
    }
  }
}

/// Mutable buffer used while accumulating a streaming tool-call fragment.
class _ToolCallBuffer {
  String id = '';
  String name = '';
  String arguments = '';
}
