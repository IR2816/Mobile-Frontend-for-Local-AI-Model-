import 'package:flutter/material.dart';

import '../services/ai_service.dart';

class OfflineScreen extends StatefulWidget {
  final VoidCallback onRetry;

  /// Optional message to display instead of the default explanation.
  final String? message;

  const OfflineScreen({super.key, required this.onRetry, this.message});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  final AiService _aiService = AiService();
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);
    final isOnline = await _aiService.checkHealth();
    if (!mounted) return;
    setState(() => _isRetrying = false);
    if (isOnline) {
      widget.onRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 80,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 24),
                const Text(
                  'AI Server Offline',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.message ??
                      'Cannot reach llama-server on localhost:8080.\n\n'
                          'Please open Termux and start the server manually, '
                          'or wait for Termux:Boot to start it automatically '
                          'on next reboot.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.6),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isRetrying ? null : _handleRetry,
                    icon: _isRetrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _isRetrying ? 'Checking…' : 'Retry Connection',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
