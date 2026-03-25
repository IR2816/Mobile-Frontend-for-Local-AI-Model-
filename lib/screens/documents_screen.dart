import 'package:flutter/material.dart';

import '../services/rag_service.dart';
import '../widgets/document_card.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final RagService _ragService = RagService();
  List<RagDocument> _documents = [];
  bool _isLoading = false;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    final docs = await _ragService.loadAll();
    if (mounted) {
      setState(() {
        _documents = docs;
        _isLoading = false;
      });
    }
  }

  Future<void> _addDocument() async {
    setState(() => _isAdding = true);
    try {
      final doc = await _ragService.addDocumentFromPicker();
      if (doc != null && mounted) {
        await _loadDocuments();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${doc.name}" added — ${doc.chunks.length} chunk${doc.chunks.length == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add document: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _confirmDelete(RagDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '"${doc.name}" will be removed from the document store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _ragService.deleteDocument(doc.id);
      await _loadDocuments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          if (_isAdding)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add document',
              onPressed: _addDocument,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 64,
                          color: Colors.white24,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No documents loaded',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white54,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap + to add a .txt or .md file.\n'
                          'The AI will search your documents when answering questions.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final doc = _documents[index];
                    return DocumentCard(
                      document: doc,
                      onDelete: () => _confirmDelete(doc),
                    );
                  },
                ),
    );
  }
}
