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
