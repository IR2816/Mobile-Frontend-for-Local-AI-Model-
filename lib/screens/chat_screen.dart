import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';
import '../models/message_status.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/inactivity_service.dart';
import '../services/memory_service.dart';
import '../services/rag_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/tool_service.dart';
import '../utils/constants.dart';
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
  // Exponential-backoff delays (seconds) used when the server is unreachable.
  static const List<int> _backoffDelays = [1, 2, 4, 8];
  static const String _lastHealthyKey = 'last_healthy_time';

  final StorageService _storageService = StorageService();
  final MemoryService _memoryService = MemoryService();
  final RagService _ragService = RagService();
  final ToolService _toolService = ToolService();
  final SettingsService _settingsService = SettingsService();
  final ExportService _exportService = ExportService();
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

  /// Whether a tool call is in progress (used to colour the typing indicator).
  bool _isToolCalling = false;

  /// Streamed assistant response being built token-by-token.
  /// Non-null only while a streaming text response is in progress.
  String? _streamingContent;

  // Connection-recovery tracking.
  int _healthCheckFailures = 0;
  DateTime? _lastHealthyTime;
  DateTime? _wentOfflineAt;
  // Prevents the ">5 min offline" warning from firing on every health check.
  bool _offlineWarningShown = false;
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

    // Load settings first so they are available before anything else.
    _settings = await _settingsService.loadAll();

    // Recreate AiService only when the URL differs from the current one.
    if (_aiService.baseUrl != _settings.serverUrl) {
      _aiService = AiService(baseUrl: _settings.serverUrl);
      _inactivityService.dispose();
      _inactivityService = InactivityService(
        aiService: _aiService,
        onTimeout: _onInactivityTimeout,
      );
    }

    // Restore persisted last-healthy timestamp.
    final prefs = await SharedPreferences.getInstance();
    final savedTime = prefs.getString(_lastHealthyKey);
    if (savedTime != null) {
      _lastHealthyTime = DateTime.tryParse(savedTime);
    }

    final isOnline = await _aiService.checkHealth();
    if (isOnline) {
      _lastHealthyTime = DateTime.now();
      _healthCheckFailures = 0;
      _wentOfflineAt = null;
      _offlineWarningShown = false;
      await prefs.setString(
        _lastHealthyKey,
        _lastHealthyTime!.toIso8601String(),
      );

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
        _startHealthChecks();
        _scrollToBottom();
      }
    } else {
      _wentOfflineAt ??= DateTime.now();
      if (mounted) {
        setState(() {
          _isServerOnline = false;
          _isChecking = false;
        });
      }
    }
  }

  // Non-periodic health check that reschedules itself with backoff.
  void _startHealthChecks() {
    _healthTimer?.cancel();
    _scheduleNextHealthCheck();
  }

  void _scheduleNextHealthCheck() {
    if (!mounted) return;
    // When offline, use exponential backoff (1 s → 2 s → 4 s → 8 s).
    // Failures beyond the last backoff index continue at the maximum delay.
    final delay = _isServerOnline
        ? AppDurations.healthCheckNormal
        : Duration(
            seconds: _backoffDelays[
                _healthCheckFailures.clamp(0, _backoffDelays.length - 1)],
          );
    _healthTimer = Timer(delay, _performHealthCheckAndReschedule);
  }

  Future<void> _performHealthCheckAndReschedule() async {
    await _periodicHealthCheck();
    _scheduleNextHealthCheck();
  }

  Future<void> _periodicHealthCheck() async {
    if (!mounted) return;
    final isOnline = await _aiService.checkHealth();
    if (!mounted) return;

    if (isOnline) {
      _lastHealthyTime = DateTime.now();
      _healthCheckFailures = 0;
      _wentOfflineAt = null;
      _offlineWarningShown = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastHealthyKey,
        _lastHealthyTime!.toIso8601String(),
      );
    } else {
      _healthCheckFailures++;
      _wentOfflineAt ??= DateTime.now();

      // Warn the user once per offline episode if unreachable for > 5 minutes.
      if (!_offlineWarningShown) {
        final downFor = DateTime.now().difference(_wentOfflineAt!);
        if (downFor >= AppDurations.offlineWarning && mounted) {
          _offlineWarningShown = true;
          final minutes = downFor.inMinutes;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Server has been unreachable for $minutes min. '
                  'Please check llama-server in Termux.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
        }
      }
    }

    if (mounted && isOnline != _isServerOnline) {
      setState(() => _isServerOnline = isOnline);
    }
  }

  Future<void> _retryHealthCheck() async {
    setState(() => _isChecking = true);
    final isOnline = await _aiService.checkHealth();
    if (mounted) {
      if (isOnline) {
        _lastHealthyTime = DateTime.now();
        _healthCheckFailures = 0;
        _wentOfflineAt = null;
        _offlineWarningShown = false;
        setState(() {
          _isServerOnline = true;
          _isChecking = false;
        });
        _inactivityService.resetTimer();
        _startHealthChecks();
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

    final userMessage = Message(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );
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
          _isToolCalling = false;
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
  Future<List<Message>> _buildApiMessages(String userQuery) async {
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
            setState(() {
              _streamingContent = contentBuffer.toString();
              _isToolCalling = false;
            });
            _scrollToBottom();
          }
        } else if (event is AiToolCallsEvent) {
          pendingToolCalls = event.toolCalls;
          if (mounted) {
            setState(() => _isToolCalling = true);
          }
        }
      }

      if (pendingToolCalls == null) {
        final assistantMessage = Message(
          role: 'assistant',
          content: contentBuffer.toString(),
          timestamp: DateTime.now(),
          status: MessageStatus.delivered,
        );
        if (mounted) {
          setState(() {
            _messages.add(assistantMessage);
            _uiItems.add(_UiItem.message(assistantMessage));
            _streamingContent = null;
            _isLoading = false;
            _isToolCalling = false;
          });
          await _storageService.saveHistory(_messages);
          _scrollToBottom();
        }
        return;
      }

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

    if (mounted) {
      setState(() {
        _streamingContent = null;
        _isLoading = false;
        _isToolCalling = false;
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
  // Message actions: delete, edit, regenerate
  //
  // NOTE: These methods use Dart's [identical] for object-reference equality
  // because messages added to [_messages] and [_uiItems] within a single
  // session always share the same instance. The lists are rebuilt from scratch
  // in [_initialize] so there is no risk of stale references from a previous
  // session.
  // -------------------------------------------------------------------------

  void _handleDeleteMessage(Message message) {
    setState(() {
      _messages.removeWhere((m) => identical(m, message));
      _uiItems.removeWhere((item) => identical(item.message, message));
    });
    _storageService.saveHistory(_messages);
  }

  Future<void> _handleEditMessage(
    Message message,
    String newContent,
  ) async {
    final msgIndex =
        _messages.indexWhere((m) => identical(m, message));
    final uiIndex =
        _uiItems.indexWhere((item) => identical(item.message, message));
    if (msgIndex < 0 || uiIndex < 0) return;

    final editedMessage = message.copyWith(
      content: newContent,
      isEdited: true,
      originalContent: message.originalContent ?? message.content,
      status: MessageStatus.sent,
    );

    // Remove the original message and everything after it. Do NOT add
    // editedMessage to _messages yet – _buildApiMessages reads from _messages
    // and editedMessage is added explicitly to apiMessages below (same pattern
    // as _sendMessage).
    setState(() {
      _messages.removeRange(msgIndex, _messages.length);
      _uiItems.removeRange(uiIndex, _uiItems.length);
      _uiItems.add(_UiItem.message(editedMessage));
      _isLoading = true;
    });
    _inactivityService.resetTimer();

    final apiMessages = await _buildApiMessages(newContent);
    apiMessages.add(editedMessage);

    // Persist the edited message now that the API context is built.
    setState(() => _messages.add(editedMessage));
    _scrollToBottom();

    try {
      await _runConversationLoop(apiMessages);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamingContent = null;
          _isToolCalling = false;
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

  Future<void> _handleRegenerateMessage(Message assistantMessage) async {
    final uiIndex = _uiItems
        .indexWhere((item) => identical(item.message, assistantMessage));
    // Walk back through _messages to find the user message that triggered
    // this assistant response.
    final msgIndex =
        _messages.indexWhere((m) => identical(m, assistantMessage));
    if (msgIndex < 0 || uiIndex < 0) return;

    int userMsgIndex = msgIndex - 1;
    while (userMsgIndex >= 0 && _messages[userMsgIndex].role != 'user') {
      userMsgIndex--;
    }
    if (userMsgIndex < 0) return;

    final userMessage = _messages[userMsgIndex];
    final userUiIndex =
        _uiItems.indexWhere((item) => identical(item.message, userMessage));

    // Remove tool results AND the assistant message from _messages (everything
    // after the user message that prompted this response).
    setState(() {
      _messages.removeRange(userMsgIndex + 1, _messages.length);
      if (userUiIndex >= 0) {
        _uiItems.removeRange(userUiIndex + 1, _uiItems.length);
      }
      _isLoading = true;
    });
    _inactivityService.resetTimer();

    // userMessage is still the last item in _messages, so _buildApiMessages
    // already includes it in the windowed history. No need to add it again.
    final apiMessages = await _buildApiMessages(userMessage.content);
    _scrollToBottom();

    try {
      await _runConversationLoop(apiMessages);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamingContent = null;
          _isToolCalling = false;
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

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  Future<void> _showExportDialog() async {
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export conversation'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('json'),
            child: const Text('JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('md'),
            child: const Text('Markdown'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('txt'),
            child: const Text('Plain text'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    try {
      late String content;
      switch (format) {
        case 'json':
          content = _exportService.toJson(_messages);
        case 'md':
          content = _exportService.toMarkdown(_messages);
        default:
          content = _exportService.toText(_messages);
      }
      final filename = _exportService.timestampedFilename(format);
      final file = await _exportService.saveToDocuments(content, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
          duration: AppDurations.animationShort,
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
      final newSettings = await _settingsService.loadAll();
      // Only recreate AiService if the server URL actually changed.
      if (newSettings.serverUrl != _settings.serverUrl) {
        _aiService = AiService(baseUrl: newSettings.serverUrl);
        // Keep InactivityService in sync with the new AiService instance.
        _inactivityService.dispose();
        _inactivityService = InactivityService(
          aiService: _aiService,
          onTimeout: _onInactivityTimeout,
        );
        _inactivityService.resetTimer();
      }
      _settings = newSettings;
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
      final offlineMessage = _buildOfflineMessage();
      return OfflineScreen(onRetry: _initialize, message: offlineMessage);
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
                        ? AppColors.onlineIndicator
                        : AppColors.offlineIndicator,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export conversation',
            onPressed: _uiItems.isEmpty ? null : _showExportDialog,
          ),
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
                    itemCount: _uiItems.length +
                        (_isLoading || _streamingContent != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _uiItems.length) {
                        if (_streamingContent != null) {
                          return ChatBubble(
                            message: Message(
                              role: 'assistant',
                              content: _streamingContent!,
                            ),
                          );
                        }
                        return TypingIndicator(
                          isToolCalling: _isToolCalling,
                        );
                      }
                      final item = _uiItems[index];
                      if (item.isToolCall) {
                        return ToolCallBubble(
                          toolName: item.toolName!,
                          description: item.description!,
                        );
                      }
                      final msg = item.message!;
                      return ChatBubble(
                        message: msg,
                        onDelete: () => _handleDeleteMessage(msg),
                        onEdit: msg.role == 'user'
                            ? (text) => _handleEditMessage(msg, text)
                            : null,
                        onRegenerate: msg.role == 'assistant'
                            ? () => _handleRegenerateMessage(msg)
                            : null,
                      );
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// Builds an informative offline message that includes how long the server
  /// has been unreachable when the duration is notable.
  String? _buildOfflineMessage() {
    if (_wentOfflineAt == null) return null;
    final downFor = DateTime.now().difference(_wentOfflineAt!);
    if (downFor.inMinutes < 1) return null;
    final lastSeenStr = _lastHealthyTime != null
        ? 'Last seen: ${_formatTime(_lastHealthyTime!)}'
        : '';
    return 'Server has been offline for ${downFor.inMinutes} min. '
        '$lastSeenStr\n\n'
        'Please open Termux and start the server manually, '
        'or wait for Termux:Boot to start it automatically.';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
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
