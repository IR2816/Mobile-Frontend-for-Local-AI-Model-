import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../services/storage_service.dart';

/// Settings screen – lets the user adjust model parameters and storage.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final StorageService _storageService = StorageService();

  late AppSettings _settings;
  bool _loading = true;

  late TextEditingController _serverUrlController;
  late TextEditingController _maxTokensController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _settingsService.loadAll();
    setState(() {
      _settings = s;
      _serverUrlController = TextEditingController(text: s.serverUrl);
      _maxTokensController =
          TextEditingController(text: s.maxTokens.toString());
      _loading = false;
    });
  }

  Future<void> _save() async {
    final updated = _settings.copyWith(
      serverUrl: _serverUrlController.text.trim().isEmpty
          ? SettingsService.defaultServerUrl
          : _serverUrlController.text.trim(),
    );
    await _settingsService.saveAll(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
      Navigator.of(context).pop(true); // signal caller to reload settings
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This will permanently delete the entire conversation history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _storageService.clearHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat history cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // --- Server ---
          _sectionHeader('Server'),
          TextField(
            controller: _serverUrlController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://localhost:8080',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // --- Generation Parameters ---
          _sectionHeader('Generation Parameters'),
          _sliderTile(
            label: 'Temperature',
            value: _settings.temperature,
            min: 0.0,
            max: 2.0,
            divisions: 40,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(temperature: v)),
          ),
          _sliderTile(
            label: 'Top-p',
            value: _settings.topP,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(topP: v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Text('Max response tokens')),
                SizedBox(
                  width: 90,
                  child: TextField(
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    ),
                    controller: _maxTokensController,
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed > 0) {
                        setState(
                          () => _settings =
                              _settings.copyWith(maxTokens: parsed),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Context Window ---
          _sectionHeader('Context Window'),
          _sliderTile(
            label: 'Messages in context',
            value: _settings.contextWindow.toDouble(),
            min: SettingsService.minContextWindow.toDouble(),
            max: SettingsService.maxContextWindow.toDouble(),
            divisions: SettingsService.maxContextWindow -
                SettingsService.minContextWindow,
            isInt: true,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(contextWindow: v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Keeps the last ${_settings.contextWindow} messages when sending '
              'to the model, preventing token-overflow on long conversations.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),

          // --- Storage ---
          _sectionHeader('Storage'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Clear chat history'),
            subtitle: const Text(
              'Permanently deletes all stored messages.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: OutlinedButton(
              onPressed: _confirmClearHistory,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              child: const Text('Clear'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Storage is capped at 500 messages / 100 MB. Older messages are '
            'automatically trimmed when the limit is reached.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _sliderTile({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    bool isInt = false,
  }) {
    final displayValue =
        isInt ? value.round().toString() : value.toStringAsFixed(2);
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          displayValue,
          style: const TextStyle(color: Colors.white70),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
