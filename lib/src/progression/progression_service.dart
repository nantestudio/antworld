import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../simulation/colony_simulation.dart';
import 'achievements.dart';
import 'progression_state.dart';
import 'unlockables.dart';

/// Service for managing player progression, XP, levels, and unlocks
class ProgressionService extends ChangeNotifier {
  ProgressionService._();
  static final instance = ProgressionService._();

  static const String _storageKey = 'antworld.progression-state';

  ProgressionState _state = const ProgressionState();
  bool _isLoaded = false;

  /// Current progression state
  ProgressionState get state => _state;

  /// Whether progression has been loaded from storage
  bool get isLoaded => _isLoaded;

  /// Current player level
  int get level => _state.level;

  /// Current total XP
  int get totalXP => _state.totalXP;

  /// XP progress towards next level (0.0 - 1.0)
  double get levelProgress => _state.levelProgress;

  /// List of newly unlocked items since last check (for UI notifications)
  final List<dynamic> pendingNotifications = [];

  /// Load progression from storage
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _state = ProgressionState.fromJson(json);
      }
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load progression: $e');
      _isLoaded = true;
    }
  }

  /// Save progression to storage
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_state.toJson());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('Failed to save progression: $e');
    }
  }

  /// Add XP and check for level up
  void addXP(int amount, {String? source}) {
    if (amount <= 0) return;

    final oldLevel = _state.level;
    int newXP = _state.totalXP + amount;
    int newLevel = _state.level;

    // Check for level ups
    while (true) {
      final xpNeeded = newLevel * 100 + 50;
      int xpAtLevel = newXP;
      for (int l = 1; l < newLevel; l++) {
        xpAtLevel -= l * 100 + 50;
      }
      if (xpAtLevel >= xpNeeded) {
        newLevel++;
      } else {
        break;
      }
    }

    _state = _state.copyWith(
      totalXP: newXP,
      level: newLevel,
    );

    // Check for new unlocks on level up
    if (newLevel > oldLevel) {
      _onLevelUp(oldLevel, newLevel);
    }

    notifyListeners();
    save();
  }

  void _onLevelUp(int oldLevel, int newLevel) {
    // Log analytics
    AnalyticsService.instance.logLevelUp(
      newLevel: newLevel,
      totalXP: _state.totalXP,
    );

    // Check for new feature unlocks
    for (final unlockable in unlockables) {
      if (unlockable.requiredLevel > oldLevel && unlockable.requiredLevel <= newLevel) {
        _unlockFeature(unlockable);
      }
    }

    // Add level up notification
    pendingNotifications.add({
      'type': 'level_up',
      'level': newLevel,
    });
  }

  void _unlockFeature(Unlockable unlockable) {
    if (_state.unlockedFeatures.contains(unlockable.id)) return;

    _state = _state.copyWith(
      unlockedFeatures: {..._state.unlockedFeatures, unlockable.id},
    );

    // Log analytics
    AnalyticsService.instance.logFeatureUnlocked(
      featureId: unlockable.id,
      level: _state.level,
    );

    // Add unlock notification
    pendingNotifications.add({
      'type': 'feature_unlock',
      'feature': unlockable,
    });
  }

  /// Check and award achievements based on current simulation state
  void checkAchievements(ColonySimulation sim) {
    final newlyUnlocked = achievements
        .where((a) =>
            !_state.unlockedAchievements.contains(a.id) &&
            a.checkCondition != null &&
            a.checkCondition!(_state, sim))
        .toList();

    for (final achievement in newlyUnlocked) {
      _unlockAchievement(achievement);
    }
  }

  /// Manually unlock an achievement (for event-triggered achievements)
  void unlockAchievementById(String achievementId) {
    final achievement = getAchievementById(achievementId);
    if (achievement != null) {
      _unlockAchievement(achievement);
    }
  }

  void _unlockAchievement(Achievement achievement) {
    if (_state.unlockedAchievements.contains(achievement.id)) return;

    _state = _state.copyWith(
      unlockedAchievements: {..._state.unlockedAchievements, achievement.id},
    );

    // Award XP
    addXP(achievement.xpReward, source: 'achievement:${achievement.id}');

    // Log analytics
    AnalyticsService.instance.logAchievementUnlocked(
      achievementId: achievement.id,
      xpReward: achievement.xpReward,
    );

    // Add achievement notification
    pendingNotifications.add({
      'type': 'achievement',
      'achievement': achievement,
    });

    notifyListeners();
    save();
  }

  /// Called when food is collected - awards periodic XP
  void onFoodCollected(int totalFood) {
    // Award 5 XP every 10 food
    final xpMilestone = (totalFood ~/ 10) * 5;
    final previousMilestone = ((totalFood - 1) ~/ 10) * 5;
    if (xpMilestone > previousMilestone) {
      addXP(5, source: 'food_collected');
    }
  }

  /// Called when a day passes - awards XP
  void onDayPassed(int day) {
    // Award 10 XP per day
    addXP(10, source: 'day_passed');
  }

  /// Called when player wins a colony battle
  void onColonyConquered() {
    // Update lifetime stats
    final conquests = (_state.lifetimeStats['colonies_conquered'] ?? 0) + 1;
    _state = _state.copyWith(
      lifetimeStats: {..._state.lifetimeStats, 'colonies_conquered': conquests},
    );

    // Award first battle achievement
    if (conquests == 1) {
      unlockAchievementById('first_battle');
    }
    // Award conqueror achievement
    if (conquests >= 3) {
      unlockAchievementById('conqueror');
    }

    // Award XP for conquest
    addXP(50, source: 'colony_conquered');
    save();
  }

  /// Called when a game starts
  void onGameStarted() {
    final gamesPlayed = (_state.lifetimeStats['games_played'] ?? 0) + 1;
    _state = _state.copyWith(
      lifetimeStats: {..._state.lifetimeStats, 'games_played': gamesPlayed},
    );
    save();
  }

  /// Called when a game ends - updates lifetime stats
  void onGameEnded(ColonySimulation sim) {
    final totalFood = (_state.lifetimeStats['total_food'] ?? 0) + sim.foodCollected.value;
    final totalDays = (_state.lifetimeStats['total_days'] ?? 0) + sim.daysPassed.value;

    _state = _state.copyWith(
      lifetimeStats: {
        ..._state.lifetimeStats,
        'total_food': totalFood,
        'total_days': totalDays,
      },
    );
    save();
  }

  /// Clear pending notifications (call after displaying them)
  void clearNotifications() {
    pendingNotifications.clear();
  }

  /// Check if a speed is unlocked
  bool isSpeedUnlocked(double speed) {
    return speed <= getMaxSpeedForLevel(_state.level);
  }

  /// Check if a colony count is unlocked
  bool isColonyCountUnlocked(int count) {
    return count <= getMaxColoniesForLevel(_state.level);
  }

  /// Check if a map size is unlocked
  bool isMapSizeUnlocked(String size) {
    return getAvailableMapSizesForLevel(_state.level).contains(size);
  }

  /// Reset progression (for testing)
  Future<void> reset() async {
    _state = const ProgressionState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
}
