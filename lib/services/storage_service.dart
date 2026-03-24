import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

class StorageService {
  static const String _historyKey = 'chat_history';

  Future<void> saveHistory(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
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
