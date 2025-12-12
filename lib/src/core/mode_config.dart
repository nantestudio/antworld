import '../simulation/colony_simulation.dart';
import '../simulation/level_layout.dart';
import '../simulation/simulation_config.dart';
import 'game_mode.dart';

typedef SimulationPredicate = bool Function(ColonySimulation simulation);

class WinCondition {
  const WinCondition({
    required this.id,
    required this.description,
    this.evaluator,
  });

  final String id;
  final String description;
  final SimulationPredicate? evaluator;

  bool evaluate(ColonySimulation simulation) {
    if (evaluator == null) {
      return false;
    }
    return evaluator!(simulation);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'description': description};
  }

  factory WinCondition.fromJson(Map<String, dynamic> json) {
    return WinCondition(
      id: json['id'] as String? ?? 'win',
      description: json['description'] as String? ?? '',
    );
  }
}

class LoseCondition {
  const LoseCondition({
    required this.id,
    required this.description,
    this.evaluator,
  });

  final String id;
  final String description;
  final SimulationPredicate? evaluator;

  bool evaluate(ColonySimulation simulation) {
    if (evaluator == null) {
      return false;
    }
    return evaluator!(simulation);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'description': description};
  }

  factory LoseCondition.fromJson(Map<String, dynamic> json) {
    return LoseCondition(
      id: json['id'] as String? ?? 'lose',
      description: json['description'] as String? ?? '',
    );
  }
}

abstract class ModeConfig {
  const ModeConfig();

  GameMode get mode;
  SimulationConfig get simulationConfig;
  bool get allowSave;
  bool get hasTimeLimit;
  Duration? get timeLimit;
  bool get trackMilestones;
  WinCondition? get winCondition;
  LoseCondition? get loseCondition;
  LevelLayout? get layout => null;

  Map<String, dynamic> toJson();
}

class SandboxModeConfig extends ModeConfig {
  const SandboxModeConfig({this.config = defaultSimulationConfig, this.seed});

  final SimulationConfig config;
  final int? seed;

  @override
  GameMode get mode => GameMode.sandbox;

  @override
  bool get allowSave => true;

  @override
  bool get hasTimeLimit => false;

  @override
  Duration? get timeLimit => null;

  @override
  bool get trackMilestones => true;

  @override
  SimulationConfig get simulationConfig => config;

  @override
  WinCondition? get winCondition => null;

  @override
  LoseCondition? get loseCondition => null;

  @override
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'seed': seed,
      'config': simulationConfigToJson(config),
    };
  }

  factory SandboxModeConfig.fromJson(Map<String, dynamic> json) {
    return SandboxModeConfig(
      seed: json['seed'] as int?,
      config: simulationConfigFromJson(
        json['config'] as Map<String, dynamic>?,
        fallback: defaultSimulationConfig,
      ),
    );
  }
}

ModeConfig modeConfigFromJson(Map<String, dynamic> json) {
  return SandboxModeConfig.fromJson(json);
}
