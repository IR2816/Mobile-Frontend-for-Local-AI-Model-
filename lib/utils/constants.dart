import 'package:flutter/material.dart';

/// App-wide constants for colours, durations and limits.
class AppColors {
  AppColors._();

  static const Color bubbleUser = Color(0xFF1565C0);
  static const Color bubbleAssistant = Color(0xFF2A2A2A);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF333333);
  static const Color codeBackground = Color(0xFF1A1A1A);
  static const Color onlineIndicator = Colors.greenAccent;
  static const Color offlineIndicator = Colors.redAccent;
  static const Color editedBadge = Colors.amber;
  static const Color toolCallColor = Colors.orange;
}

/// Strings for the typing indicator animation.
class TypingPhrases {
  TypingPhrases._();

  static const List<String> normal = [
    'AI is thinking…',
    'Generating response…',
    'Processing…',
    'Composing reply…',
  ];

  static const List<String> toolCalling = [
    'Using a tool…',
    'Calling function…',
    'Executing tool…',
    'Fetching results…',
  ];
}

/// Duration constants used throughout the app.
class AppDurations {
  AppDurations._();

  static const Duration healthCheckNormal = Duration(seconds: 30);
  static const Duration offlineWarning = Duration(minutes: 5);
  static const Duration inactivityTimeout = Duration(minutes: 15);
  static const Duration streamTimeout = Duration(seconds: 120);
  static const Duration animationShort = Duration(milliseconds: 300);
  static const Duration typingPhraseRotation = Duration(seconds: 3);
}
