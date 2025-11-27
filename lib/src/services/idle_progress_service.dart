import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/game_mode.dart';
import '../progression/progression_service.dart';
import '../simulation/colony_simulation.dart';
import '../state/unified_storage.dart';

class IdleSessionSnapshot {
  const IdleSessionSnapshot({
    required this.timestamp,
    required this.mode,
    required this.colonyCount,
    required this.antCount,
    required this.foodCollected,
    required this.daysSurvived,
  });

  final DateTime timestamp;
  final GameMode mode;
  final int colonyCount;
  final int antCount;
  final int foodCollected;
  final int daysSurvived;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'mode': mode.name,
      'colonyCount': colonyCount,
      'antCount': antCount,
      'foodCollected': foodCollected,
      'daysSurvived': daysSurvived,
    };
  }

  factory IdleSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? GameMode.sandbox.name;
    final mode = GameMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => GameMode.sandbox,
    );
    return IdleSessionSnapshot(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      mode: mode,
      colonyCount: json['colonyCount'] as int? ?? 1,
      antCount: json['antCount'] as int? ?? 0,
      foodCollected: json['foodCollected'] as int? ?? 0,
      daysSurvived: json['daysSurvived'] as int? ?? 1,
    );
  }

  IdleSessionSnapshot copyWith({
    DateTime? timestamp,
    int? colonyCount,
    int? antCount,
    int? foodCollected,
    int? daysSurvived,
  }) {
    return IdleSessionSnapshot(
      timestamp: timestamp ?? this.timestamp,
      mode: mode,
      colonyCount: colonyCount ?? this.colonyCount,
      antCount: antCount ?? this.antCount,
      foodCollected: foodCollected ?? this.foodCollected,
      daysSurvived: daysSurvived ?? this.daysSurvived,
    );
  }

  static IdleSessionSnapshot fromSimulation(
    GameMode mode,
    ColonySimulation? simulation,
  ) {
    if (simulation == null) {
      return IdleSessionSnapshot(
        timestamp: DateTime.now(),
        mode: mode,
        colonyCount: 1,
        antCount: 0,
        foodCollected: 0,
        daysSurvived: 1,
      );
    }
    return IdleSessionSnapshot(
      timestamp: DateTime.now(),
      mode: mode,
      colonyCount: simulation.config.colonyCount,
      antCount: simulation.antCount.value,
      foodCollected: simulation.foodCollected.value,
      daysSurvived: simulation.daysPassed.value,
    );
  }
}

class IdleReward {
  const IdleReward({
    required this.food,
    required this.xp,
    required this.awayDuration,
    required this.mode,
    required this.antsContributing,
  });

  final int food;
  final int xp;
  final Duration awayDuration;
  final GameMode mode;
  final int antsContributing;
}

class IdleState {
  const IdleState({this.snapshot, this.bankedFood = 0});

  final IdleSessionSnapshot? snapshot;
  final int bankedFood;

  IdleState copyWith({IdleSessionSnapshot? snapshot, int? bankedFood}) {
    return IdleState(
      snapshot: snapshot ?? this.snapshot,
      bankedFood: bankedFood ?? this.bankedFood,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankedFood': bankedFood,
      'snapshot': snapshot?.toJson(),
    };
  }

  factory IdleState.fromJson(Map<String, dynamic> json) {
    final snapshotData =
        json['snapshot'] as Map<dynamic, dynamic>? ?? const {};
    return IdleState(
      bankedFood: json['bankedFood'] as int? ?? 0,
      snapshot: snapshotData.isNotEmpty
          ? IdleSessionSnapshot.fromJson(
              Map<String, dynamic>.from(snapshotData),
            )
          : null,
    );
  }
}

class IdleProgressService extends ChangeNotifier {
  IdleProgressService._({UnifiedStorage? storage})
    : _storage = storage ?? UnifiedStorage();

  static final IdleProgressService instance = IdleProgressService._();

  final UnifiedStorage _storage;
  IdleState _state = const IdleState();
  IdleReward? _pendingReward;
  bool _loaded = false;

  IdleReward? get pendingReward => _pendingReward;
  int get bankedFood => _state.bankedFood;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.loadIdleState();
    if (raw.isNotEmpty) {
      _state = IdleState.fromJson(raw);
    }
    _loaded = true;
  }

  Future<void> recordSession({
    required GameMode mode,
    ColonySimulation? simulation,
  }) async {
    if (!_shouldRecord(mode)) {
      return;
    }
    final snapshot = IdleSessionSnapshot.fromSimulation(mode, simulation);
    _state = _state.copyWith(snapshot: snapshot);
    await _persist();
  }

  Future<IdleReward?> computePendingReward() async {
    if (!_loaded) {
      await load();
    }
    final snapshot = _state.snapshot;
    if (snapshot == null) {
      return null;
    }
    final now = DateTime.now();
    final away = now.difference(snapshot.timestamp);
    // Ignore very short gaps
    if (away.inMinutes < 5) {
      return null;
    }

    final reward = _calculateReward(snapshot, away);
    _pendingReward = reward;

    // Reset the snapshot timestamp to avoid double counting
    final updatedSnapshot = snapshot.copyWith(timestamp: now);
    _state = _state.copyWith(snapshot: updatedSnapshot);
    await _persist();
    notifyListeners();
    return reward;
  }

  void claimPendingReward() {
    final reward = _pendingReward;
    if (reward == null) return;
    _pendingReward = null;
    _state = _state.copyWith(bankedFood: _state.bankedFood + reward.food);
    ProgressionService.instance.addXP(reward.xp, source: 'idle_reward');
    _persist();
    notifyListeners();
  }

  int takeBankedFood() {
    if (_state.bankedFood <= 0) return 0;
    final amount = _state.bankedFood;
    _state = _state.copyWith(bankedFood: 0);
    _persist();
    notifyListeners();
    return amount;
  }

  IdleReward _calculateReward(
    IdleSessionSnapshot snapshot,
    Duration away,
  ) {
    // Cap away time to avoid runaway rewards
    final cappedHours = math.min(away.inMinutes / 60.0, 12.0);
    final activityScore = snapshot.antCount * 0.35 +
        snapshot.foodCollected * 0.08 +
        snapshot.daysSurvived * 2.0;
    final colonyMultiplier = math.max(1, snapshot.colonyCount) * 0.9;
    final food = (activityScore * colonyMultiplier * (cappedHours * 0.6))
        .round()
        .clamp(5, 2000);
    final xp = (10 + snapshot.daysSurvived * 2 + snapshot.antCount * 0.05)
        .round() *
        cappedHours
        .round();

    return IdleReward(
      food: food,
      xp: xp,
      awayDuration: Duration(
        minutes: math.min(away.inMinutes, (12 * 60).round()),
      ),
      mode: snapshot.mode,
      antsContributing: snapshot.antCount,
    );
  }

  bool _shouldRecord(GameMode mode) {
    // Offline rewards make sense for sandbox/zen where long-running colonies live
    return mode == GameMode.sandbox || mode == GameMode.zenMode;
  }

  Future<void> _persist() async {
    await _storage.saveIdleState(_state.toJson());
  }
}
