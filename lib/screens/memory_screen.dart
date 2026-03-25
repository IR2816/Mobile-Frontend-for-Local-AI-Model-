import 'package:flutter/material.dart';

import '../models/memory_entry.dart';
import '../services/memory_service.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final MemoryService _memoryService = MemoryService();
  List<MemoryEntry> _memories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    final memories = await _memoryService.loadAll();
    if (mounted) {
      setState(() {
        _memories = memories;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDelete(MemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memory?'),
        content: Text(
          '"${entry.content.length > 80 ? '${entry.content.substring(0, 80)}…' : entry.content}" '
          'will be permanently deleted.',
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
      await _memoryService.delete(entry.id);
      await _loadMemories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Long-Term Memory')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1A1A2E),
            child: const Text(
              '💡 The AI can save memories automatically during chat. '
              'Relevant memories are injected into each conversation as context.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _memories.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.psychology_rounded,
                                size: 64,
                                color: Colors.white24,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No memories saved',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white54,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Ask the AI to remember something and it '
                                'will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _memories.length,
                        itemBuilder: (context, index) {
                          final entry = _memories[index];
                          return _MemoryTile(
                            entry: entry,
                            onDelete: () => _confirmDelete(entry),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  final MemoryEntry entry;
  final VoidCallback onDelete;

  const _MemoryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.psychology_rounded,
                size: 18,
                color: Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: entry.tags
                          .map(
                            (t) => Chip(
                              label: Text(
                                t,
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              backgroundColor: const Color(0xFF2A2A3E),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(entry.createdAt),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Colors.redAccent,
              ),
              tooltip: 'Delete memory',
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
