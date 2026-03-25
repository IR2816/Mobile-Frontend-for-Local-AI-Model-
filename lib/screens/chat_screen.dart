import 'dart:async';

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/inactivity_service.dart';
import '../services/memory_service.dart';
import '../services/rag_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/tool_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/tool_call_bubble.dart';
import '../widgets/typing_indicator.dart';
import 'documents_screen.dart';
import 'memory_screen.dart';
import 'offline_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  final StorageService _storageService = StorageService();
  final MemoryService _memoryService = MemoryService();
  final RagService _ragService = RagService();
  final ToolService _toolService = ToolService();
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late AiService _aiService;
  late InactivityService _inactivityService;

  AppSettings _settings = const AppSettings(
    serverUrl: SettingsService.defaultServerUrl,
    temperature: SettingsService.defaultTemperature,
    topP: SettingsService.defaultTopP,
    maxTokens: SettingsService.defaultMaxTokens,
    contextWindow: SettingsService.defaultContextWindow,
  );

  /// The full conversation history (stored/loaded via StorageService).
  List<Message> _messages = [];

  /// UI-only items for rendering: messages + tool-call indicators.
  final List<_UiItem> _uiItems = [];

  bool _isLoading = false;
  bool _isServerOnline = false;
  bool _isChecking = true;

  /// Streamed assistant response being built token-by-token.
  /// Non-null only while a streaming text response is in progress.
  String? _streamingContent;

  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _aiService = AiService(baseUrl: SettingsService.defaultServerUrl);
    _inactivityService = InactivityService(
      aiService: _aiService,
      onTimeout: _onInactivityTimeout,
    );
    _initialize();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _inactivityService.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Initialisation & health
  // -------------------------------------------------------------------------

  Future<void> _initialize() async {
    setState(() => _isChecking = true);

    // Load settings first so they're available before anything else.
    _settings = await _settingsService.loadAll();
    _aiService = AiService(baseUrl: _settings.serverUrl);

    // Recreate InactivityService so it references the correctly-configured
    // AiService (in case the server URL has changed since last run).
    _inactivityService.dispose();
    _inactivityService = InactivityService(
      aiService: _aiService,
      onTimeout: _onInactivityTimeout,
    );

    final isOnline = await _aiService.checkHealth();
    if (isOnline) {
      final history = await _storageService.loadHistory();
      if (mounted) {
        setState(() {
          _isServerOnline = true;
          _isChecking = false;
          _messages = history;
          _uiItems.clear();
          for (final m in history) {
            if (m.role != 'system' && m.role != 'tool') {
              _uiItems.add(_UiItem.message(m));
            }
          }
        });
        _inactivityService.resetTimer();
        _startPeriodicHealthChecks();
        _scrollToBottom();
      }
    } else {
      if (mounted) {
        setState(() {
          _isServerOnline = false;
          _isChecking = false;
        });
      }
    }
  }

  void _startPeriodicHealthChecks() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      _healthCheckInterval,
      (_) => _periodicHealthCheck(),
    );
  }

  Future<void> _periodicHealthCheck() async {
    if (!mounted) return;
    final isOnline = await _aiService.checkHealth();
    if (mounted && isOnline != _isServerOnline) {
      setState(() => _isServerOnline = isOnline);
    }
  }

  Future<void> _retryHealthCheck() async {
    setState(() => _isChecking = true);
    final isOnline = await _aiService.checkHealth();
    if (mounted) {
      if (isOnline) {
        setState(() {
          _isServerOnline = true;
          _isChecking = false;
        });
        _inactivityService.resetTimer();
        _startPeriodicHealthChecks();
      } else {
        setState(() {
          _isServerOnline = false;
          _isChecking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server is still offline.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Message sending
  // -------------------------------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    final userMessage = Message(role: 'user', content: text);
    _textController.clear();
    _inactivityService.resetTimer();

    // Build context window: system prompts + last N messages + new user msg.
    final apiMessages = await _buildApiMessages(text);
    apiMessages.add(userMessage);

    setState(() {
      _messages.add(userMessage);
      _uiItems.add(_UiItem.message(userMessage));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      await _runConversationLoop(apiMessages);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamingContent = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Builds the list of messages to send to the API.
  ///
  /// Prepends a base system prompt, relevant memory context, and RAG context,
  /// then applies a sliding context window over the stored conversation.
  Future<List<Message>> _buildApiMessages(String userQuery) async {
    // Base system prompt.
    final context = <Message>[
      const Message(role: 'system', content: kDefaultSystemPrompt),
    ];

    final memoryMsg =
        await _memoryService.buildMemoryContextMessage(userQuery);
    if (memoryMsg != null) context.add(memoryMsg);

    final ragContext = await _ragService.search(userQuery);
    if (ragContext != null) {
      context.add(Message(role: 'system', content: ragContext));
    }

    // Sliding window: keep the last [contextWindow] non-system messages.
    final history = _messages.where((m) => m.role != 'system').toList();
    final windowed = history.length > _settings.contextWindow
        ? history.sublist(history.length - _settings.contextWindow)
        : history;

    return [...context, ...windowed];
  }

  /// Runs the streaming function-calling loop until the model returns text.
  Future<void> _runConversationLoop(List<Message> apiMessages) async {
    const int maxToolRounds = 5;
    int round = 0;

    while (round < maxToolRounds) {
      final contentBuffer = StringBuffer();
      List<ToolCall>? pendingToolCalls;

      // Stream the next turn from the model.
      await for (final event in _aiService.streamMessage(
        apiMessages,
        tools: ToolService.toolSchemas,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
        topP: _settings.topP,
      )) {
        if (event is AiTextToken) {
          contentBuffer.write(event.token);
          if (mounted) {
            setState(() => _streamingContent = contentBuffer.toString());
            _scrollToBottom();
          }
        } else if (event is AiToolCallsEvent) {
          pendingToolCalls = event.toolCalls;
        }
      }

      if (pendingToolCalls == null) {
        // Plain text reply — finalise the streaming bubble.
        final assistantMessage = Message(
          role: 'assistant',
          content: contentBuffer.toString(),
        );
        if (mounted) {
          setState(() {
            _messages.add(assistantMessage);
            _uiItems.add(_UiItem.message(assistantMessage));
            _streamingContent = null;
            _isLoading = false;
          });
          await _storageService.saveHistory(_messages);
          _scrollToBottom();
        }
        return;
      }

      // Tool call(s) requested — hide the streaming bubble and process them.
      if (mounted) {
        setState(() => _streamingContent = null);
      }

      for (final toolCall in pendingToolCalls) {
        final description =
            toolCallDescription(toolCall.name, toolCall.argumentsJson);

        if (mounted) {
          setState(() {
            _uiItems.add(
              _UiItem.toolCall(
                toolName: toolCall.name,
                description: description,
              ),
            );
          });
          _scrollToBottom();
        }

        final result = await _toolService.execute(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          argumentsJson: toolCall.argumentsJson,
        );

        final toolResultMessage = Message(
          role: 'tool',
          content: result.result,
          toolCallId: result.toolCallId,
          toolName: result.toolName,
        );
        apiMessages.add(toolResultMessage);
        _messages.add(toolResultMessage);
      }

      round++;
    }

    // Exceeded max tool-call rounds.
    if (mounted) {
      setState(() {
        _streamingContent = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Tool call limit reached. Try rephrasing your message.'),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // UI helpers
  // -------------------------------------------------------------------------

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmClearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This will permanently delete the conversation history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.clearHistory();
      if (mounted) {
        setState(() {
          _messages = [];
          _uiItems.clear();
        });
      }
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SettingsScreen()),
    );
    if (changed == true && mounted) {
      // Reload settings and recreate AiService with potentially new server URL.
      _settings = await _settingsService.loadAll();
      _aiService = AiService(baseUrl: _settings.serverUrl);
    }
  }

  void _onInactivityTimeout(String message) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineScreen(
          message: message,
          onRetry: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const ChatScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isServerOnline) {
      return OfflineScreen(onRetry: _initialize);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Qwen2.5-7B'),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _retryHealthCheck,
              child: Semantics(
                label:
                    'Server status: ${_isServerOnline ? 'online' : 'offline'}. '
                    'Tap to retry health check.',
                button: true,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _isServerOnline
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_rounded),
            tooltip: 'Documents',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DocumentsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.psychology_rounded),
            tooltip: 'Memory',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MemoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _uiItems.isEmpty ? null : _confirmClearChat,
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _uiItems.isEmpty && _streamingContent == null
                ? const Center(
                    child: Text(
                      'Start a conversation…',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        _uiItems.length +
                        (_isLoading || _streamingContent != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _uiItems.length) {
                        // Show streamed content if tokens are arriving;
                        // otherwise show the animated typing indicator.
                        if (_streamingContent != null) {
                          return ChatBubble(
                            message: Message(
                              role: 'assistant',
                              content: _streamingContent!,
                            ),
                          );
                        }
                        return const TypingIndicator();
                      }
                      final item = _uiItems[index];
                      if (item.isToolCall) {
                        return ToolCallBubble(
                          toolName: item.toolName!,
                          description: item.description!,
                        );
                      }
                      return ChatBubble(message: item.message!);
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isLoading ? null : _sendMessage,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discriminated union for items in the chat UI list.
// ---------------------------------------------------------------------------

class _UiItem {
  final Message? message;
  final String? toolName;
  final String? description;

  const _UiItem._({this.message, this.toolName, this.description});

  factory _UiItem.message(Message m) => _UiItem._(message: m);
  factory _UiItem.toolCall({
    required String toolName,
    required String description,
  }) =>
      _UiItem._(toolName: toolName, description: description);

  bool get isToolCall => toolName != null;
}
