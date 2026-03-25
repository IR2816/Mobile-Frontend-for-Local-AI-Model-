/// Represents the result of executing a tool during a function-calling cycle.
class ToolResult {
  final String toolCallId;
  final String toolName;
  final String result;
  final bool isError;

  const ToolResult({
    required this.toolCallId,
    required this.toolName,
    required this.result,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
        'tool_call_id': toolCallId,
        'tool_name': toolName,
        'result': result,
        'is_error': isError,
      };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
        toolCallId: json['tool_call_id'] as String,
        toolName: json['tool_name'] as String,
        result: json['result'] as String,
        isError: json['is_error'] as bool? ?? false,
      );
}
