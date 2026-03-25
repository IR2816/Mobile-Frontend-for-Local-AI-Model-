import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/memory_entry.dart';
import '../models/message.dart';

/// Manages long-term memories stored as a JSON file in app-local storage.
class MemoryService {
  static const String _fileName = 'memories.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<MemoryEntry>> loadAll() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => MemoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<MemoryEntry> entries) async {
    final file = await _getFile();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<MemoryEntry> add({
    required String content,
    List<String> tags = const [],
  }) async {
    final entries = await loadAll();
    final entry = MemoryEntry(
      id: _generateId(),
      content: content,
      createdAt: DateTime.now(),
      tags: tags,
    );
    entries.add(entry);
    await _saveAll(entries);
    return entry;
  }

  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    await _saveAll(entries);
  }

  /// Returns memories whose content or tags contain [query] (case-insensitive).
  Future<List<MemoryEntry>> search(String query) async {
    final lower = query.toLowerCase();
    final entries = await loadAll();
    return entries.where((e) {
      if (e.content.toLowerCase().contains(lower)) return true;
      return e.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  /// Builds a system-message [Message] that injects relevant memories
  /// as context. Returns null when no relevant memories are found.
  Future<Message?> buildMemoryContextMessage(String userQuery) async {
    final relevant = await search(userQuery);
    if (relevant.isEmpty) return null;

    final buffer = StringBuffer(
      'The following information from long-term memory may be relevant '
      'to the current conversation:\n\n',
    );
    for (final entry in relevant) {
      buffer.write('• ${entry.content}');
      if (entry.tags.isNotEmpty) {
        buffer.write(' [tags: ${entry.tags.join(', ')}]');
      }
      buffer.write('\n');
    }

    return Message(role: 'system', content: buffer.toString().trimRight());
  }

  /// Simple pseudo-random ID: timestamp combined with an LCG (linear
  /// congruential generator) step using Knuth's multiplicative constants.
  String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = (ts * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF;
    return '${ts.toRadixString(16)}-${rand.toRadixString(16)}';
  }
}
