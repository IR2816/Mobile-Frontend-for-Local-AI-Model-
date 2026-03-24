import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: _isUser ? theme.colorScheme.primary : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                _isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight:
                _isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: _isUser
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
                    backgroundColor: Color(0xFF1A1A1A),
                  ),
                  codeblockDecoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
      ),
    );
  }
}
