import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/game_mode.dart';
import '../core/player_progress.dart';

class StorageKeys {
  static const String sandboxSave = 'sandbox_save';
  static const String playerProgress = 'player_progress';
  static const String cosmetics = 'cosmetics';
  static const String settings = 'settings';
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
    final savedAt =
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now();
    return SaveData(
      mode: GameMode.sandbox,
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
    await prefs.setString(StorageKeys.sandboxSave, payload);
  }

  Future<SaveData?> loadModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(StorageKeys.sandboxSave);
    if (raw == null) {
      return null;
    }
    return SaveData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    await prefs.remove(StorageKeys.sandboxSave);
  }

  Future<bool> hasModeState(GameMode mode) async {
    final prefs = await _prefsFuture;
    return prefs.containsKey(StorageKeys.sandboxSave);
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
}
