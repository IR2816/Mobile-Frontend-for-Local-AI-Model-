import 'dart:convert';

import '../models/tool_result.dart';
import 'memory_service.dart';
import 'rag_service.dart';
import 'web_search_service.dart';

/// Central service for tool execution during function-calling cycles.
class ToolService {
  final WebSearchService _webSearch;
  final MemoryService _memory;
  final RagService _rag;

  ToolService({
    WebSearchService? webSearch,
    MemoryService? memory,
    RagService? rag,
  })  : _webSearch = webSearch ?? WebSearchService(),
        _memory = memory ?? MemoryService(),
        _rag = rag ?? RagService();

  /// The list of tool schemas to include in every API request.
  static const List<Map<String, dynamic>> toolSchemas = [
    {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description':
            'Search the web for current information using DuckDuckGo. '
                'Use when you need up-to-date facts, news, or general knowledge '
                'that may not be in your training data.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query string.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_memory',
        'description':
            'Search the user\'s long-term memory for information relevant '
                'to a query. Use this to recall facts the user has asked you to remember.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The topic or keyword to search memories for.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'save_memory',
        'description':
            'Save a piece of information to the user\'s long-term memory '
                'so it can be recalled in future conversations.',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {
              'type': 'string',
              'description': 'The information to remember.',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Optional list of tags to categorise the memory (e.g. ["work", "project"]).',
            },
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_documents',
        'description':
            'Search the user\'s uploaded documents for information relevant '
                'to a query. Use this to answer questions based on the user\'s files.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The topic or keywords to search for in documents.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_current_time',
        'description':
            'Returns the current date and time. Use when the user asks '
                'what time or date it is.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
  ];

  /// Executes the named tool with the given [argumentsJson] string and
  /// returns a [ToolResult].
  Future<ToolResult> execute({
    required String toolCallId,
    required String toolName,
    required String argumentsJson,
  }) async {
    try {
      final args = argumentsJson.isNotEmpty
          ? jsonDecode(argumentsJson) as Map<String, dynamic>
          : <String, dynamic>{};

      final result = await _dispatch(toolName, args);
      return ToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        result: result,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        result: 'Tool "$toolName" failed: $e',
        isError: true,
      );
    }
  }

  Future<String> _dispatch(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case 'web_search':
        final query = args['query'] as String? ?? '';
        if (query.isEmpty) return 'No query provided for web_search.';
        return _webSearch.search(query);

      case 'read_memory':
        final query = args['query'] as String? ?? '';
        if (query.isEmpty) return 'No query provided for read_memory.';
        final entries = await _memory.search(query);
        if (entries.isEmpty) return 'No memories found matching "$query".';
        return entries.map((e) {
          final tagStr =
              e.tags.isNotEmpty ? ' [tags: ${e.tags.join(', ')}]' : '';
          return '• ${e.content}$tagStr';
        }).join('\n');

      case 'save_memory':
        final content = args['content'] as String? ?? '';
        if (content.isEmpty) return 'No content provided for save_memory.';
        final rawTags = args['tags'];
        final tags = rawTags is List
            ? rawTags.cast<String>()
            : <String>[];
        await _memory.add(content: content, tags: tags);
        return 'Memory saved: "$content"';

      case 'search_documents':
        final query = args['query'] as String? ?? '';
        if (query.isEmpty) return 'No query provided for search_documents.';
        final result = await _rag.search(query);
        return result ?? 'No relevant document excerpts found for "$query".';

      case 'get_current_time':
        final now = DateTime.now();
        return '${_weekday(now.weekday)}, '
            '${now.day} ${_month(now.month)} ${now.year} — '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';

      default:
        return 'Unknown tool: $toolName';
    }
  }

  static String _weekday(int d) => const [
        '',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][d];

  static String _month(int m) => const [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][m];
}
