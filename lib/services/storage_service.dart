import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

class StorageService {
  static const String _historyKey = 'chat_history';

  /// Maximum number of messages retained in storage.
  static const int _maxMessages = 500;

  /// Maximum JSON byte size for stored history (100 MB).
  static const int _maxJsonBytes = 100 * 1024 * 1024;

  Future<void> saveHistory(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();

    // Trim to the most recent [_maxMessages] messages.
    var trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;

    // Further trim if the JSON representation exceeds [_maxJsonBytes].
    var json = jsonEncode(trimmed.map((m) => m.toJson()).toList());
    while (json.length > _maxJsonBytes && trimmed.isNotEmpty) {
      // Remove the oldest 10 % of messages at a time.
      final removeCount = (trimmed.length * 0.1).ceil().clamp(1, trimmed.length);
      trimmed = trimmed.sublist(removeCount);
      json = jsonEncode(trimmed.map((m) => m.toJson()).toList());
    }

    await prefs.setString(_historyKey, json);
  }

  Future<List<Message>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_historyKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
