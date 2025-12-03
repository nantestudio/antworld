import '../simulation/ant.dart';
import 'game_mode.dart';

abstract class GameEvent {
  const GameEvent();
}

class FoodCollectedEvent extends GameEvent {
  const FoodCollectedEvent({required this.amount, required this.colonyId});

  final int amount;
  final int colonyId;
}

class AntBornEvent extends GameEvent {
  const AntBornEvent({required this.caste, required this.colonyId});

  final AntCaste caste;
  final int colonyId;
}

class MilestoneReachedEvent extends GameEvent {
  const MilestoneReachedEvent(this.milestoneId);

  final String milestoneId;
}

class DayAdvancedEvent extends GameEvent {
  const DayAdvancedEvent({required this.day});

  final int day;
}

class LevelCompletedEvent extends GameEvent {
  const LevelCompletedEvent({
    required this.levelId,
    required this.stars,
    required this.mode,
  });

  final String levelId;
  final int stars;
  final GameMode mode;
}

class GameModeChangedEvent extends GameEvent {
  const GameModeChangedEvent({required this.mode});

  final GameMode mode;
}

class SimulationLifecycleEvent extends GameEvent {
  const SimulationLifecycleEvent.starting({required this.mode})
    : phase = SimulationLifecyclePhase.starting;
  const SimulationLifecycleEvent.ended({required this.mode})
    : phase = SimulationLifecyclePhase.ended;

  final GameMode mode;
  final SimulationLifecyclePhase phase;

  bool get isStarting => phase == SimulationLifecyclePhase.starting;
}

enum SimulationLifecyclePhase { starting, ended }

// ============================================================================
// Hive Mind AI Events
// ============================================================================

/// Emitted when the AI Hive Mind makes a strategic decision
class HiveMindDecisionAppliedEvent extends GameEvent {
  const HiveMindDecisionAppliedEvent({
    required this.reasoning,
    required this.directiveCount,
  });

  final String reasoning;
  final int directiveCount;
}

/// Emitted when the AI stores a memory for future context
class HiveMindMemoryStoredEvent extends GameEvent {
  const HiveMindMemoryStoredEvent({
    required this.category,
    required this.content,
  });

  final String category;
  final String content;
}

/// Emitted when the AI starts/stops processing
class HiveMindProcessingEvent extends GameEvent {
  const HiveMindProcessingEvent({required this.isProcessing});

  final bool isProcessing;
}

// ============================================================================
// Mother Nature Events
// ============================================================================

/// Base class for Mother Nature environmental events
abstract class NatureEventBase extends GameEvent {
  const NatureEventBase({
    required this.message,
    required this.isPositive,
  });

  final String message;
  final bool isPositive;
}

/// Emitted when a nature event occurs (food bloom, collapse, etc.)
class NatureEventOccurred extends NatureEventBase {
  const NatureEventOccurred({
    required this.eventType,
    required this.positionX,
    required this.positionY,
    required super.message,
    required super.isPositive,
    this.severity,
  });

  final String eventType;
  final double positionX;
  final double positionY;
  final String? severity;
}

/// Emitted when the season changes
class SeasonChangedEvent extends GameEvent {
  const SeasonChangedEvent({
    required this.season,
    required this.seasonIndex,
  });

  final String season;
  final int seasonIndex;
}
