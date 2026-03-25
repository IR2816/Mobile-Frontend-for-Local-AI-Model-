import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/message.dart';
import '../utils/constants.dart';

class ChatBubble extends StatelessWidget {
  final Message message;

  /// Called when the user requests to delete this message.
  final VoidCallback? onDelete;

  /// Called with the new text when the user edits a user message.
  /// Only provided for user messages.
  final void Function(String newContent)? onEdit;

  /// Called when the user requests to regenerate this assistant message.
  /// Only provided for assistant messages.
  final VoidCallback? onRegenerate;

  const ChatBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onEdit,
    this.onRegenerate,
  });

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: _isUser
            ? theme.colorScheme.primary
            : AppColors.bubbleAssistant,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft:
              _isUser ? const Radius.circular(16) : Radius.zero,
          bottomRight:
              _isUser ? Radius.zero : const Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _isUser
              ? Text(
                  message.content,
                  style: const TextStyle(color: Colors.white),
                )
              : MarkdownBody(
                  data: message.content,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(color: Colors.white70),
                    code: const TextStyle(
                      color: Colors.greenAccent,
                      backgroundColor: AppColors.codeBackground,
                    ),
                    codeblockDecoration: const BoxDecoration(
                      color: AppColors.codeBackground,
                      borderRadius:
                          BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                ),
          if (message.isEdited) ...[
            const SizedBox(height: 4),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 11,
                  color: AppColors.editedBadge,
                ),
                SizedBox(width: 3),
                Text(
                  'Edited',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.editedBadge,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActionsMenu(context),
        child: bubble,
      ),
    );
  }

  void _showActionsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Copy – always available
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy message'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard.')),
                );
              },
            ),
            // Edit – user messages only
            if (_isUser && onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit & resend'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showEditDialog(context);
                },
              ),
            // Regenerate – assistant messages only
            if (!_isUser && onRegenerate != null)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Regenerate response'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onRegenerate!();
                },
              ),
            // Delete – always available
            if (onDelete != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete message',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    // Track disposal to avoid double-dispose when both a button tap and the
    // .then() callback would otherwise call dispose().
    var controllerDisposed = false;
    void disposeController() {
      if (!controllerDisposed) {
        controllerDisposed = true;
        controller.dispose();
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Edit your message…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              disposeController();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty) {
                disposeController();
                Navigator.of(ctx).pop();
                onEdit!(newContent);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    ).then((_) => disposeController());
  }
}
