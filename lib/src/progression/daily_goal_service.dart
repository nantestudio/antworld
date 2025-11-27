import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/event_bus.dart';
import '../core/game_event.dart';
import '../services/analytics_service.dart';
import '../state/unified_storage.dart';
import 'progression_service.dart';

enum DailyGoalType { collectFood, hatchAnts, surviveDays }

class DailyGoal {
  const DailyGoal({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.target,
    required this.rewardXp,
    this.progress = 0,
    this.claimed = false,
  });

  final String id;
  final String title;
  final String description;
  final DailyGoalType type;
  final int target;
  final int progress;
  final int rewardXp;
  final bool claimed;

  bool get isComplete => progress >= target;

  DailyGoal copyWith({
    int? progress,
    bool? claimed,
  }) {
    return DailyGoal(
      id: id,
      title: title,
      description: description,
      type: type,
      target: target,
      rewardXp: rewardXp,
      progress: progress ?? this.progress,
      claimed: claimed ?? this.claimed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.name,
      'target': target,
      'progress': progress,
      'rewardXp': rewardXp,
      'claimed': claimed,
    };
  }

  factory DailyGoal.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? DailyGoalType.collectFood.name;
    final type = DailyGoalType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => DailyGoalType.collectFood,
    );
    return DailyGoal(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: type,
      target: json['target'] as int? ?? 1,
      progress: json['progress'] as int? ?? 0,
      rewardXp: json['rewardXp'] as int? ?? 10,
      claimed: json['claimed'] as bool? ?? false,
    );
  }
}

class DailyGoalState {
  const DailyGoalState({
    required this.dayId,
    required this.generatedAt,
    required this.goals,
    this.currentStreak = 0,
  });

  final String dayId;
  final DateTime generatedAt;
  final List<DailyGoal> goals;
  final int currentStreak;

  Map<String, dynamic> toJson() {
    return {
      'dayId': dayId,
      'generatedAt': generatedAt.toIso8601String(),
      'currentStreak': currentStreak,
      'goals': goals.map((g) => g.toJson()).toList(),
    };
  }

  factory DailyGoalState.fromJson(Map<String, dynamic> json) {
    final goalsData = (json['goals'] as List<dynamic>? ?? [])
        .map(
          (data) => DailyGoal.fromJson(
            Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
          ),
        )
        .toList();
    return DailyGoalState(
      dayId: json['dayId'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      currentStreak: json['currentStreak'] as int? ?? 0,
      goals: List.unmodifiable(goalsData),
    );
  }

  DailyGoalState copyWith({
    String? dayId,
    DateTime? generatedAt,
    List<DailyGoal>? goals,
    int? currentStreak,
  }) {
    return DailyGoalState(
      dayId: dayId ?? this.dayId,
      generatedAt: generatedAt ?? this.generatedAt,
      goals: goals ?? this.goals,
      currentStreak: currentStreak ?? this.currentStreak,
    );
  }
}

class DailyGoalService extends ChangeNotifier {
  DailyGoalService._({UnifiedStorage? storage})
    : _storage = storage ?? UnifiedStorage();

  static final DailyGoalService instance = DailyGoalService._();

  final UnifiedStorage _storage;
  DailyGoalState? _state;
  bool _loaded = false;
  StreamSubscription? _foodSub;
  StreamSubscription? _hatchSub;
  StreamSubscription? _daySub;

  List<DailyGoal> get goals => _state?.goals ?? const [];
  int get currentStreak => _state?.currentStreak ?? 0;
  bool get isLoaded => _loaded;
  String get dayId => _state?.dayId ?? _todayId();

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.loadDailyGoals();
    if (raw.isNotEmpty) {
      _state = DailyGoalState.fromJson(raw);
    }
    _ensureForToday();
    _loaded = true;
  }

  Future<void> attach(GameEventBus bus) async {
    if (!_loaded) {
      await load();
    }
    _foodSub?.cancel();
    _hatchSub?.cancel();
    _daySub?.cancel();

    _foodSub = bus.on<FoodCollectedEvent>().listen((event) {
      _incrementProgress(DailyGoalType.collectFood, event.amount);
    });
    _hatchSub = bus.on<AntBornEvent>().listen((event) {
      if (event.caste.name == 'egg') {
        return;
      }
      _incrementProgress(DailyGoalType.hatchAnts, 1);
    });
    _daySub = bus.on<DayAdvancedEvent>().listen((event) {
      _incrementProgress(DailyGoalType.surviveDays, 1);
    });
  }

  Future<void> disposeListeners() async {
    await _foodSub?.cancel();
    await _hatchSub?.cancel();
    await _daySub?.cancel();
  }

  Future<void> claimCompletedGoals() async {
    if (_state == null) return;
    final updated = <DailyGoal>[];
    var claimedCount = 0;
    for (final goal in _state!.goals) {
      if (goal.isComplete && !goal.claimed) {
        ProgressionService.instance.addXP(
          goal.rewardXp,
          source: 'daily_goal:${goal.id}',
        );
        claimedCount++;
        updated.add(goal.copyWith(claimed: true));
      } else {
        updated.add(goal);
      }
    }
    _state = _state!.copyWith(goals: updated);
    await _persist();
    notifyListeners();

    if (claimedCount > 0) {
      AnalyticsService.instance.logLevelUp(
        newLevel: ProgressionService.instance.level,
        totalXP: ProgressionService.instance.totalXP,
      );
    }
  }

  void _incrementProgress(DailyGoalType type, int delta) {
    if (_state == null || delta <= 0) return;
    final updated = _state!.goals.map((goal) {
      if (goal.type != type || goal.isComplete) return goal;
      final nextProgress = (goal.progress + delta).clamp(0, goal.target);
      return goal.copyWith(progress: nextProgress);
    }).toList();
    _state = _state!.copyWith(goals: updated);
    _persist();
    notifyListeners();
  }

  void _ensureForToday() {
    final today = _todayId();
    if (_state == null || _state!.dayId != today) {
      final streak =
          _state == null ? 0 : (_state!.currentStreak + 1).clamp(0, 30);
      _state = DailyGoalState(
        dayId: today,
        generatedAt: DateTime.now(),
        goals: _generateGoals(),
        currentStreak: streak,
      );
      _persist();
      notifyListeners();
    }
  }

  List<DailyGoal> _generateGoals() {
    final rng = math.Random(DateTime.now().millisecondsSinceEpoch);
    final goals = <DailyGoal>[
      DailyGoal(
        id: 'collect_${rng.nextInt(9999)}',
        title: 'Stockpile',
        description: 'Collect food around the tunnels.',
        type: DailyGoalType.collectFood,
        target: 80 + rng.nextInt(120),
        rewardXp: 25,
      ),
      DailyGoal(
        id: 'hatch_${rng.nextInt(9999)}',
        title: 'New Workers',
        description: 'Hatch fresh ants to grow the colony.',
        type: DailyGoalType.hatchAnts,
        target: 5 + rng.nextInt(8),
        rewardXp: 35,
      ),
      DailyGoal(
        id: 'survive_${rng.nextInt(9999)}',
        title: 'Keep Marching',
        description: 'Survive in-game days without collapse.',
        type: DailyGoalType.surviveDays,
        target: 2 + rng.nextInt(3),
        rewardXp: 30,
      ),
    ];
    return goals;
  }

  String _todayId() {
    final now = DateTime.now().toUtc();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  Future<void> _persist() async {
    final state = _state;
    if (state == null) return;
    await _storage.saveDailyGoals(state.toJson());
  }
}
