class Message {
  final String role;
  final String content;

  /// For tool-result messages (role == 'tool'), the ID of the tool call
  /// this is responding to.
  final String? toolCallId;

  /// For tool-result messages, the name of the tool that was called.
  final String? toolName;

  const Message({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolName != null) map['name'] = toolName;
    return map;
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        role: json['role'] as String,
        content: json['content'] as String,
        toolCallId: json['tool_call_id'] as String?,
        toolName: json['name'] as String?,
      );
}
