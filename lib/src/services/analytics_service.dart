import 'package:firebase_analytics/firebase_analytics.dart';

/// Analytics service for tracking key game events
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Track when user starts a new colony
  Future<void> logGameStart({
    required int colonyCount,
    required int mapCols,
    required int mapRows,
  }) async {
    await _analytics.logEvent(
      name: 'game_start',
      parameters: {
        'colony_count': colonyCount,
        'map_cols': mapCols,
        'map_rows': mapRows,
        'map_size': '${mapCols}x$mapRows',
      },
    );
  }

  /// Track when user loads a saved game
  Future<void> logGameLoad({
    required int daysPassed,
    required int totalFood,
    required int antCount,
  }) async {
    await _analytics.logEvent(
      name: 'game_load',
      parameters: {
        'days_passed': daysPassed,
        'total_food': totalFood,
        'ant_count': antCount,
      },
    );
  }

  /// Track map generation
  Future<void> logMapGenerated({
    required String sizePreset,
    required int cols,
    required int rows,
    required int colonyCount,
    required int seed,
  }) async {
    await _analytics.logEvent(
      name: 'map_generated',
      parameters: {
        'size_preset': sizePreset,
        'cols': cols,
        'rows': rows,
        'colony_count': colonyCount,
        'seed': seed,
      },
    );
  }

  /// Track colony takeover (major game event)
  Future<void> logColonyTakeover({
    required int winnerColonyId,
    required int defeatedColonyId,
    required int convertedAnts,
    required int daysPassed,
  }) async {
    await _analytics.logEvent(
      name: 'colony_takeover',
      parameters: {
        'winner_colony_id': winnerColonyId,
        'defeated_colony_id': defeatedColonyId,
        'converted_ants': convertedAnts,
        'days_passed': daysPassed,
      },
    );
  }

  /// Track food milestones (100, 500, 1000, etc)
  Future<void> logFoodMilestone({
    required int colonyId,
    required int milestone,
    required int daysPassed,
  }) async {
    await _analytics.logEvent(
      name: 'food_milestone',
      parameters: {
        'colony_id': colonyId,
        'milestone': milestone,
        'days_passed': daysPassed,
      },
    );
  }

  /// Track day milestones (10, 50, 100, etc)
  Future<void> logDayMilestone({
    required int day,
    required int totalAnts,
    required int totalFood,
  }) async {
    await _analytics.logEvent(
      name: 'day_milestone',
      parameters: {
        'day': day,
        'total_ants': totalAnts,
        'total_food': totalFood,
      },
    );
  }

  /// Track simulation speed changes
  Future<void> logSpeedChanged({required double speedMultiplier}) async {
    await _analytics.logEvent(
      name: 'speed_changed',
      parameters: {
        'speed_multiplier': speedMultiplier,
      },
    );
  }

  /// Track brush mode usage
  Future<void> logBrushUsed({required String brushMode}) async {
    await _analytics.logEvent(
      name: 'brush_used',
      parameters: {
        'brush_mode': brushMode,
      },
    );
  }

  /// Track game save
  Future<void> logGameSaved({
    required int daysPassed,
    required int antCount,
    required int totalFood,
  }) async {
    await _analytics.logEvent(
      name: 'game_saved',
      parameters: {
        'days_passed': daysPassed,
        'ant_count': antCount,
        'total_food': totalFood,
      },
    );
  }

  /// Set user property for session tracking
  Future<void> setUserColonyPreference(int colonyCount) async {
    await _analytics.setUserProperty(
      name: 'preferred_colony_count',
      value: colonyCount.toString(),
    );
  }
}
