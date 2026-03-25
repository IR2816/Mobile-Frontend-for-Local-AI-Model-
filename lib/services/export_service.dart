import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/message.dart';

/// Exports conversation history in multiple formats and saves to the device's
/// Documents directory.
class ExportService {
  // ---------------------------------------------------------------------------
  // Format generators
  // ---------------------------------------------------------------------------

  /// Returns the conversation encoded as a pretty-printed JSON string.
  String toJson(List<Message> messages) {
    final visible = messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'message_count': visible.length,
      'messages': visible.map((m) => m.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Returns the conversation formatted as Markdown.
  String toMarkdown(List<Message> messages) {
    final buf = StringBuffer();
    buf.writeln('# Conversation Export');
    buf.writeln();
    buf.writeln('*Exported: ${_formatDateTime(DateTime.now())}*');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    for (final m in messages) {
      if (m.role == 'user') {
        buf.writeln('## 👤 User');
        if (m.isEdited) buf.writeln('*✏️ Edited*');
        buf.writeln();
        buf.writeln(m.content);
        buf.writeln();
      } else if (m.role == 'assistant') {
        buf.writeln('## 🤖 Assistant');
        buf.writeln();
        buf.writeln(m.content);
        buf.writeln();
      }
    }
    return buf.toString();
  }

  /// Returns the conversation as plain text.
  String toText(List<Message> messages) {
    final buf = StringBuffer();
    buf.writeln('Conversation Export – ${_formatDateTime(DateTime.now())}');
    buf.writeln('=' * 60);
    for (final m in messages) {
      if (m.role == 'user') {
        buf.writeln('\nUser${m.isEdited ? " (edited)" : ""}:');
        buf.writeln(m.content);
        buf.writeln('-' * 40);
      } else if (m.role == 'assistant') {
        buf.writeln('\nAssistant:');
        buf.writeln(m.content);
        buf.writeln('-' * 40);
      }
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // File I/O
  // ---------------------------------------------------------------------------

  /// Saves [content] to the app's documents directory with the given [filename].
  /// Returns the [File] that was written.
  Future<File> saveToDocuments(String content, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    return file;
  }

  /// Generates a timestamped filename with the given [extension] (e.g. 'json').
  String timestampedFilename(String extension) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_p(now.month)}${_p(now.day)}_${_p(now.hour)}${_p(now.minute)}';
    return 'conversation_$stamp.$extension';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatDateTime(DateTime dt) =>
      '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
      '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';

  String _p(int n) => n.toString().padLeft(2, '0');
}
