import 'message_status.dart';

class Message {
  final String role;
  final String content;

  /// For tool-result messages (role == 'tool'), the ID of the tool call
  /// this is responding to.
  final String? toolCallId;

  /// For tool-result messages, the name of the tool that was called.
  final String? toolName;

  /// Whether this message was edited by the user after it was originally sent.
  final bool isEdited;

  /// When the message was sent or received.
  final DateTime? timestamp;

  /// The original content before the user edited the message.
  final String? originalContent;

  /// Human-readable description of a send/receive failure, if any.
  final String? errorMessage;

  /// Lifecycle status of this message.
  final MessageStatus status;

  const Message({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
    this.isEdited = false,
    this.timestamp,
    this.originalContent,
    this.errorMessage,
    this.status = MessageStatus.sent,
  });

  Message copyWith({
    String? role,
    String? content,
    String? toolCallId,
    String? toolName,
    bool? isEdited,
    DateTime? timestamp,
    String? originalContent,
    String? errorMessage,
    MessageStatus? status,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      isEdited: isEdited ?? this.isEdited,
      timestamp: timestamp ?? this.timestamp,
      originalContent: originalContent ?? this.originalContent,
      errorMessage: errorMessage ?? this.errorMessage,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolName != null) map['name'] = toolName;
    if (isEdited) map['is_edited'] = true;
    if (timestamp != null) map['timestamp'] = timestamp!.toIso8601String();
    if (originalContent != null) map['original_content'] = originalContent;
    if (errorMessage != null) map['error_message'] = errorMessage;
    map['status'] = status.name;
    return map;
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        role: json['role'] as String,
        content: json['content'] as String,
        toolCallId: json['tool_call_id'] as String?,
        toolName: json['name'] as String?,
        isEdited: json['is_edited'] as bool? ?? false,
        timestamp: json['timestamp'] == null
            ? null
            : DateTime.tryParse(json['timestamp'] as String),
        originalContent: json['original_content'] as String?,
        errorMessage: json['error_message'] as String?,
        status: _parseStatus(json['status'] as String?),
      );

  static MessageStatus _parseStatus(String? name) {
    if (name == null) return MessageStatus.sent;
    try {
      return MessageStatus.values.byName(name);
    } catch (_) {
      return MessageStatus.sent;
    }
  }
}
