import 'dart:async';

import 'package:flutter/widgets.dart';

import 'ai_service.dart';

/// Manages a 15-minute inactivity timer.
///
/// * Call [resetTimer] every time the user sends a message.
/// * Provide an [onTimeout] callback that is invoked (on the UI thread) when
///   the timer fires.  The callback receives the message to show on the
///   offline screen.
/// * Observes the app lifecycle so the timer is cancelled whenever the app is
///   backgrounded and restarted when it comes back to the foreground.
class InactivityService with WidgetsBindingObserver {
  static const Duration _timeout = Duration(minutes: 15);
  static const String timeoutMessage =
      'Server stopped due to inactivity. '
      'Start it again from Termux or wait for next reboot.';

  final AiService _aiService;
  final void Function(String message) onTimeout;

  Timer? _timer;

  InactivityService({
    required AiService aiService,
    required this.onTimeout,
  }) : _aiService = aiService {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Resets (or starts) the inactivity timer.
  void resetTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, _handleTimeout);
  }

  /// Cancels the inactivity timer without triggering the timeout callback.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Removes the lifecycle observer and cancels the timer.
  void dispose() {
    cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _handleTimeout() async {
    _timer = null;
    await _aiService.stopServer();
    onTimeout(timeoutMessage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      cancel();
    } else if (state == AppLifecycleState.resumed) {
      resetTimer();
    }
  }
}
