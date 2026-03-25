import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Searches the web using the DuckDuckGo Instant Answer API.
///
/// Returns a human-readable summary string. Never throws — returns an
/// error description string on failure so the AI can relay it to the user.
class WebSearchService {
  static const String _baseUrl = 'https://api.duckduckgo.com/';

  Future<String> search(String query) async {
    // Check connectivity first.
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none) ||
        connectivityResult.isEmpty) {
      return 'Web search is unavailable: no internet connection.';
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'q': query,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      });

      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return 'Web search failed: server returned ${response.statusCode}.';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _buildSummary(query, data);
    } catch (e) {
      return 'Web search failed: $e';
    }
  }

  String _buildSummary(String query, Map<String, dynamic> data) {
    final parts = <String>[];

    final abstractText = (data['AbstractText'] as String? ?? '').trim();
    final abstractSource = (data['AbstractSource'] as String? ?? '').trim();
    if (abstractText.isNotEmpty) {
      final source =
          abstractSource.isNotEmpty ? ' (Source: $abstractSource)' : '';
      parts.add('$abstractText$source');
    }

    final answer = (data['Answer'] as String? ?? '').trim();
    if (answer.isNotEmpty) {
      parts.add('Quick answer: $answer');
    }

    final definition = (data['Definition'] as String? ?? '').trim();
    final definitionSource =
        (data['DefinitionSource'] as String? ?? '').trim();
    if (definition.isNotEmpty) {
      final source =
          definitionSource.isNotEmpty ? ' (Source: $definitionSource)' : '';
      parts.add('Definition: $definition$source');
    }

    final relatedTopics = data['RelatedTopics'] as List<dynamic>? ?? [];
    final relatedSnippets = <String>[];
    for (final topic in relatedTopics.take(3)) {
      if (topic is Map<String, dynamic>) {
        final text = (topic['Text'] as String? ?? '').trim();
        if (text.isNotEmpty) relatedSnippets.add(text);
      }
    }
    if (relatedSnippets.isNotEmpty) {
      parts.add('Related: ${relatedSnippets.join(' | ')}');
    }

    if (parts.isEmpty) {
      return 'No instant answer found for "$query". '
          'Try a more specific query.';
    }

    return parts.join('\n\n');
  }
}
