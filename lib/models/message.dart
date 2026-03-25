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

  const Message({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
    this.isEdited = false,
  });

  Message copyWith({
    String? role,
    String? content,
    String? toolCallId,
    String? toolName,
    bool? isEdited,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      isEdited: isEdited ?? this.isEdited,
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
    return map;
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        role: json['role'] as String,
        content: json['content'] as String,
        toolCallId: json['tool_call_id'] as String?,
        toolName: json['name'] as String?,
        isEdited: json['is_edited'] as bool? ?? false,
      );
}
