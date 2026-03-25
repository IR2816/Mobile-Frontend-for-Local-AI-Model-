/// Represents a single long-term memory entry stored locally.
class MemoryEntry {
  final String id;
  final String content;
  final DateTime createdAt;
  final List<String> tags;

  const MemoryEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'tags': tags,
      };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
        id: json['id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        tags: (json['tags'] as List<dynamic>).cast<String>(),
      );
}
