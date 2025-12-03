import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/game_mode.dart';
import '../core/player_progress.dart';

class StorageKeys {
  static const String sandboxSave = 'sandbox_save';
  static const String campaignProgress = 'campaign_progress';
  static const String playerProgress = 'player_progress';
  static const String dailyGoals = 'daily_goals';
  static const String cosmetics = 'cosmetics';
  static const String settings = 'settings';
  static const String idleState = 'idle_state';
}

const String _saveVersion = '1.0.0';

class SaveData {
  const SaveData({
    required this.mode,
    required this.savedAt,
    required this.modeData,
    required this.playerProgress,
    required this.simulationState,
    this.version = _saveVersion,
  });

  final GameMode mode;
  final DateTime savedAt;
  final String version;
  final Map<String, dynamic> modeData;
  final PlayerProgress playerProgress;
  final Map<String, dynamic> simulationState;

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'savedAt': savedAt.toIso8601String(),
      'version': version,
      'modeData': modeData,
      'playerProgress': playerProgress.toJson(),
      'simulationState': simulationState,
    };
  }

  factory SaveData.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? GameMode.sandbox.name;
    final mode = GameMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => GameMode.sandbox,
    );
    final savedAt =
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now();
    return SaveData(
      mode: mode,
      savedAt: savedAt,
      version: json['version'] as String? ?? _saveVersion,
      modeData: Map<String, dynamic>.from(
        json['modeData'] as Map<dynamic, dynamic>? ?? const {},
      ),
      playerProgress: json['playerProgress'] != null
          ? PlayerProgress.fromJson(
              Map<String, dynamic>.from(
                json['playerProgress'] as Map<dynamic, dynamic>,
              ),
            )
          : PlayerProgress.initial(),
      simulationState: Map<String, dynamic>.from(
        json['simulationState'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }
}

class UnifiedStorage {
  UnifiedStorage({SharedPreferences? preferences})
    : _prefsFuture = preferences != null
          ? Future.value(preferences)
          : SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  Future<void> saveModeState(SaveData save) async {
    final prefs = await _prefsFuture;
    final payload = jsonEncode(save.toJson());
    await prefs.setString(_keyForMode(save.mode), payload);
  }

  Future<SaveData?> loadModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_keyForMode(mode));
    if (raw == null) {
      return null;
    }
    return SaveData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    await prefs.remove(_keyForMode(mode));
  }

  Future<bool> hasModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    return prefs.containsKey(_keyForMode(mode));
  }

  Future<void> savePlayerProgress(PlayerProgress progress) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      StorageKeys.playerProgress,
      jsonEncode(progress.toJson()),
    );
  }

  Future<PlayerProgress> loadPlayerProgress() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.playerProgress);
    if (raw == null) {
      return PlayerProgress.initial();
    }
    return PlayerProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCampaignProgress(Map<String, dynamic> progress) async {
    final prefs = await _prefsFuture;
    await prefs.setString(StorageKeys.campaignProgress, jsonEncode(progress));
  }

  Future<Map<String, dynamic>> loadCampaignProgress() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.campaignProgress);
    if (raw == null) {
      return const {};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveDailyGoals(Map<String, dynamic> goals) async {
    final prefs = await _prefsFuture;
    await prefs.setString(StorageKeys.dailyGoals, jsonEncode(goals));
  }

  Future<Map<String, dynamic>> loadDailyGoals() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.dailyGoals);
    if (raw == null) {
      return const {};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveCosmetics(Map<String, dynamic> cosmetics) async {
    final prefs = await _prefsFuture;
    await prefs.setString(StorageKeys.cosmetics, jsonEncode(cosmetics));
  }

  Future<Map<String, dynamic>> loadCosmetics() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.cosmetics);
    if (raw == null) {
      return const {};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await _prefsFuture;
    await prefs.setString(StorageKeys.settings, jsonEncode(settings));
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.settings);
    if (raw == null) {
      return const {};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveIdleState(Map<String, dynamic> state) async {
    final prefs = await _prefsFuture;
    await prefs.setString(StorageKeys.idleState, jsonEncode(state));
  }

  Future<Map<String, dynamic>> loadIdleState() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.idleState);
    if (raw == null) {
      return const {};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  String _keyForMode(GameMode mode) {
    switch (mode) {
      case GameMode.sandbox:
        return StorageKeys.sandboxSave;
      case GameMode.zenMode:
        return '${StorageKeys.idleState}_zen';
      case GameMode.campaign:
        return '${StorageKeys.idleState}_campaign';
      case GameMode.dailyChallenge:
        return '${StorageKeys.idleState}_daily';
      case GameMode.aiLab:
        return '${StorageKeys.idleState}_ailab';
    }
  }
}
