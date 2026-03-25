import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user-configurable settings.
class AppSettings {
  final String serverUrl;
  final double temperature;
  final double topP;
  final int maxTokens;
  final int contextWindow;

  const AppSettings({
    required this.serverUrl,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.contextWindow,
  });

  AppSettings copyWith({
    String? serverUrl,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? contextWindow,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      contextWindow: contextWindow ?? this.contextWindow,
    );
  }
}

/// Loads and saves app settings from SharedPreferences.
class SettingsService {
  static const String _serverUrlKey = 'server_url';
  static const String _temperatureKey = 'temperature';
  static const String _topPKey = 'top_p';
  static const String _maxTokensKey = 'max_tokens';
  static const String _contextWindowKey = 'context_window';

  static const String defaultServerUrl = 'http://localhost:8080';
  static const double defaultTemperature = 0.7;
  static const double defaultTopP = 1.0;
  static const int defaultMaxTokens = 512;
  static const int defaultContextWindow = 20;

  /// Minimum and maximum allowed context window sizes.
  static const int minContextWindow = 5;
  static const int maxContextWindow = 25;

  /// Loads all settings in a single SharedPreferences call.
  Future<AppSettings> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      serverUrl: prefs.getString(_serverUrlKey) ?? defaultServerUrl,
      temperature: prefs.getDouble(_temperatureKey) ?? defaultTemperature,
      topP: prefs.getDouble(_topPKey) ?? defaultTopP,
      maxTokens: prefs.getInt(_maxTokensKey) ?? defaultMaxTokens,
      contextWindow: prefs.getInt(_contextWindowKey) ?? defaultContextWindow,
    );
  }

  Future<void> saveAll(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, settings.serverUrl);
    await prefs.setDouble(_temperatureKey, settings.temperature);
    await prefs.setDouble(_topPKey, settings.topP);
    await prefs.setInt(_maxTokensKey, settings.maxTokens);
    await prefs.setInt(_contextWindowKey, settings.contextWindow);
  }
}
