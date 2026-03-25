import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

class StorageService {
  static const String _historyKey = 'chat_history';

  /// Maximum number of messages retained in storage.
  static const int _maxMessages = 500;

  /// Minimum number of messages to retain – never trim below this count.
  static const int _minMessages = 50;

  /// Maximum JSON byte size for stored history (100 MB).
  static const int _maxJsonBytes = 100 * 1024 * 1024;

  Future<void> saveHistory(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();

    // Trim to the most recent [_maxMessages] messages.
    var trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;

    // Further trim if the JSON representation exceeds [_maxJsonBytes].
    // Remove 25 % of messages per iteration for faster convergence, but never
    // go below [_minMessages].
    var json = jsonEncode(trimmed.map((m) => m.toJson()).toList());
    while (json.length > _maxJsonBytes && trimmed.length > _minMessages) {
      final removable = trimmed.length - _minMessages;
      final removeCount =
          ((trimmed.length * 0.25).ceil()).clamp(1, removable);
      final before = trimmed.length;
      trimmed = trimmed.sublist(removeCount);
      json = jsonEncode(trimmed.map((m) => m.toJson()).toList());
      debugPrint(
        '[StorageService] Trimmed ${before - trimmed.length} messages '
        '(${trimmed.length} remaining, JSON=${json.length}b).',
      );
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
