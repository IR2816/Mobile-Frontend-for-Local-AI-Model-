import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a stored RAG document with its text chunks.
class RagDocument {
  final String id;
  final String name;
  final List<String> chunks;

  const RagDocument({
    required this.id,
    required this.name,
    required this.chunks,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chunks': chunks,
      };

  factory RagDocument.fromJson(Map<String, dynamic> json) => RagDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        chunks: (json['chunks'] as List<dynamic>).cast<String>(),
      );
}

/// Manages a collection of user documents for simple keyword-based RAG.
class RagService {
  static const String _fileName = 'rag_documents.json';
  static const int _chunkSize = 500;
  static const int _chunkOverlap = 100;
  static const int _topK = 3;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<RagDocument>> loadAll() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => RagDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<RagDocument> docs) async {
    final file = await _getFile();
    await file.writeAsString(
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
  }

  /// Opens the file picker, reads the selected file, chunks it, and stores it.
  /// Returns the created [RagDocument] or null if the user cancelled.
  Future<RagDocument?> addDocumentFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final pickedFile = result.files.first;
    final path = pickedFile.path;
    if (path == null) return null;

    final content = await File(path).readAsString();
    final chunks = _splitIntoChunks(content);
    final doc = RagDocument(
      id: _generateId(),
      name: pickedFile.name,
      chunks: chunks,
    );

    final docs = await loadAll();
    docs.add(doc);
    await _saveAll(docs);
    return doc;
  }

  Future<void> deleteDocument(String id) async {
    final docs = await loadAll();
    docs.removeWhere((d) => d.id == id);
    await _saveAll(docs);
  }

  /// Searches all chunks across all documents for [query] and returns
  /// the top-[_topK] most relevant chunks as a single context string.
  /// Returns null when no documents are loaded.
  Future<String?> search(String query) async {
    final docs = await loadAll();
    if (docs.isEmpty) return null;

    final queryTerms =
        query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 2).toList();

    final scored = <_ScoredChunk>[];
    for (final doc in docs) {
      for (final chunk in doc.chunks) {
        final lower = chunk.toLowerCase();
        int score = 0;
        for (final term in queryTerms) {
          score += term.allMatches(lower).length;
        }
        if (score > 0) {
          scored.add(_ScoredChunk(docName: doc.name, chunk: chunk, score: score));
        }
      }
    }

    if (scored.isEmpty) return null;

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(_topK).toList();

    final buffer = StringBuffer(
      'Relevant excerpts from your documents:\n\n',
    );
    for (int i = 0; i < top.length; i++) {
      buffer.write('[${top[i].docName}]\n${top[i].chunk.trim()}\n\n');
    }
    return buffer.toString().trimRight();
  }

  List<String> _splitIntoChunks(String text) {
    assert(_chunkSize > _chunkOverlap,
        '_chunkSize must be greater than _chunkOverlap to avoid infinite loop');
    final chunks = <String>[];
    final step = _chunkSize - _chunkOverlap;
    int start = 0;
    while (start < text.length) {
      final end = (start + _chunkSize).clamp(0, text.length);
      chunks.add(text.substring(start, end));
      start += step;
    }
    return chunks;
  }

  /// Simple pseudo-random ID: timestamp combined with an LCG (linear
  /// congruential generator) step using Knuth's multiplicative constants.
  String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = (ts * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF;
    return '${ts.toRadixString(16)}-${rand.toRadixString(16)}';
  }
}

class _ScoredChunk {
  final String docName;
  final String chunk;
  final int score;

  const _ScoredChunk({
    required this.docName,
    required this.chunk,
    required this.score,
  });
}
