import 'package:flutter/material.dart';

import '../services/rag_service.dart';

/// Displays a single RAG document with its name, chunk count, and a delete
/// button.
class DocumentCard extends StatelessWidget {
  final RagDocument document;
  final VoidCallback onDelete;

  const DocumentCard({
    super.key,
    required this.document,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: ListTile(
        leading: const Icon(Icons.description_rounded, color: Colors.white54),
        title: Text(
          document.name,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${document.chunks.length} chunk${document.chunks.length == 1 ? '' : 's'}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          tooltip: 'Delete document',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
