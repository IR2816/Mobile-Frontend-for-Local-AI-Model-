/// Lifecycle status of a chat message.
enum MessageStatus {
  /// Message is queued but has not yet been sent to the server.
  pending,

  /// Message has been sent to the server.
  sent,

  /// Server confirmed receipt / the assistant response has been delivered.
  delivered,

  /// The message failed (see [Message.errorMessage] for details).
  error,
}
