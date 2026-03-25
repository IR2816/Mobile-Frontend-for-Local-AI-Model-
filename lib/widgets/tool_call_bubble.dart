import 'package:flutter/material.dart';

/// Displays a subtle bubble indicating the AI is using a tool.
class ToolCallBubble extends StatelessWidget {
  final String toolName;
  final String description;

  const ToolCallBubble({
    super.key,
    required this.toolName,
    required this.description,
  });

  static IconData _iconFor(String toolName) {
    switch (toolName) {
      case 'web_search':
        return Icons.search_rounded;
      case 'read_memory':
        return Icons.psychology_rounded;
      case 'save_memory':
        return Icons.save_rounded;
      case 'search_documents':
        return Icons.description_rounded;
      case 'get_current_time':
        return Icons.access_time_rounded;
      default:
        return Icons.build_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: theme.colorScheme.primary.withAlpha(100),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(toolName),
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                description,
                style: TextStyle(
                  color: theme.colorScheme.primary.withAlpha(200),
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Returns a human-readable description for a given tool name.
String toolCallDescription(String toolName, String argumentsJson) {
  try {
    switch (toolName) {
      case 'web_search':
        return 'Searching the web…';
      case 'read_memory':
        return 'Reading from memory…';
      case 'save_memory':
        return 'Saving to memory…';
      case 'search_documents':
        return 'Searching your documents…';
      case 'get_current_time':
        return 'Checking the current time…';
      default:
        return 'Using tool: $toolName…';
    }
  } catch (_) {
    return 'Using tool: $toolName…';
  }
}
