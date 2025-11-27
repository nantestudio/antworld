import '../simulation/colony_simulation.dart';
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

class LevelObjective {
  const LevelObjective({
    required this.id,
    required this.description,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String description;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() {
    return {'id': id, 'description': description, 'data': data};
  }

  factory LevelObjective.fromJson(Map<String, dynamic> json) {
    return LevelObjective(
      id: json['id'] as String? ?? 'objective',
      description: json['description'] as String? ?? '',
      data:
          (json['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }
}

class StarCondition {
  const StarCondition({
    required this.id,
    required this.description,
    this.threshold,
  });

  final String id;
  final String description;
  final num? threshold;

  Map<String, dynamic> toJson() {
    return {'id': id, 'description': description, 'threshold': threshold};
  }

  factory StarCondition.fromJson(Map<String, dynamic> json) {
    return StarCondition(
      id: json['id'] as String? ?? 'star',
      description: json['description'] as String? ?? '',
      threshold: json['threshold'] as num?,
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

class ZenModeConfig extends ModeConfig {
  const ZenModeConfig({
    this.config = defaultSimulationConfig,
    this.customTimeLimit,
  });

  final SimulationConfig config;
  final Duration? customTimeLimit;

  @override
  GameMode get mode => GameMode.zenMode;

  @override
  bool get allowSave => true;

  @override
  bool get hasTimeLimit => customTimeLimit != null;

  @override
  Duration? get timeLimit => customTimeLimit;

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
      'timeLimit': customTimeLimit?.inSeconds,
      'config': simulationConfigToJson(config),
    };
  }

  factory ZenModeConfig.fromJson(Map<String, dynamic> json) {
    final seconds = json['timeLimit'] as int?;
    return ZenModeConfig(
      customTimeLimit: seconds != null ? Duration(seconds: seconds) : null,
      config: simulationConfigFromJson(
        json['config'] as Map<String, dynamic>?,
        fallback: defaultSimulationConfig,
      ),
    );
  }
}

class CampaignLevelConfig extends ModeConfig {
  const CampaignLevelConfig({
    required this.levelId,
    required this.objective,
    this.starConditions = const <StarCondition>[],
    this.config = defaultSimulationConfig,
    this.timeLimitOverride,
    this.win,
    this.lose,
  });

  final String levelId;
  final LevelObjective objective;
  final List<StarCondition> starConditions;
  final SimulationConfig config;
  final Duration? timeLimitOverride;
  final WinCondition? win;
  final LoseCondition? lose;

  @override
  GameMode get mode => GameMode.campaign;

  @override
  bool get allowSave => false;

  @override
  bool get hasTimeLimit => timeLimitOverride != null;

  @override
  Duration? get timeLimit => timeLimitOverride;

  @override
  bool get trackMilestones => true;

  @override
  SimulationConfig get simulationConfig => config;

  @override
  WinCondition? get winCondition => win;

  @override
  LoseCondition? get loseCondition => lose;

  @override
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'levelId': levelId,
      'objective': objective.toJson(),
      'timeLimit': timeLimitOverride?.inSeconds,
      'starConditions': starConditions.map((c) => c.toJson()).toList(),
      'config': simulationConfigToJson(config),
      'winCondition': winCondition?.toJson(),
      'loseCondition': loseCondition?.toJson(),
    };
  }

  factory CampaignLevelConfig.fromJson(Map<String, dynamic> json) {
    final stars = (json['starConditions'] as List<dynamic>? ?? [])
        .map(
          (data) => StarCondition.fromJson(
            Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
          ),
        )
        .toList();
    final timeLimit = json['timeLimit'] as int?;
    final objectiveData = Map<String, dynamic>.from(
      (json['objective'] as Map<dynamic, dynamic>? ?? const {}),
    );
    return CampaignLevelConfig(
      levelId: json['levelId'] as String? ?? 'level',
      objective: LevelObjective.fromJson(objectiveData),
      starConditions: List.unmodifiable(stars),
      timeLimitOverride: timeLimit != null
          ? Duration(seconds: timeLimit)
          : null,
      config: simulationConfigFromJson(
        json['config'] as Map<String, dynamic>?,
        fallback: defaultSimulationConfig,
      ),
      win: (json['winCondition'] as Map?) != null
          ? WinCondition.fromJson(
              Map<String, dynamic>.from(
                json['winCondition'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
      lose: (json['loseCondition'] as Map?) != null
          ? LoseCondition.fromJson(
              Map<String, dynamic>.from(
                json['loseCondition'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
    );
  }
}

class DailyChallengeModeConfig extends ModeConfig {
  const DailyChallengeModeConfig({
    required this.challengeId,
    required this.generatedAt,
    this.config = defaultSimulationConfig,
    this.timeLimitDuration = const Duration(minutes: 20),
    this.allowSaves = false,
    this.win,
    this.lose,
  });

  final String challengeId;
  final DateTime generatedAt;
  final SimulationConfig config;
  final Duration? timeLimitDuration;
  final bool allowSaves;
  final WinCondition? win;
  final LoseCondition? lose;

  @override
  GameMode get mode => GameMode.dailyChallenge;

  @override
  bool get allowSave => allowSaves;

  @override
  bool get hasTimeLimit => timeLimitDuration != null;

  @override
  Duration? get timeLimit => timeLimitDuration;

  @override
  bool get trackMilestones => false;

  @override
  SimulationConfig get simulationConfig => config;

  @override
  WinCondition? get winCondition => win;

  @override
  LoseCondition? get loseCondition => lose;

  @override
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'challengeId': challengeId,
      'generatedAt': generatedAt.toIso8601String(),
      'timeLimit': timeLimitDuration?.inSeconds,
      'allowSave': allowSaves,
      'config': simulationConfigToJson(config),
      'winCondition': winCondition?.toJson(),
      'loseCondition': loseCondition?.toJson(),
    };
  }

  factory DailyChallengeModeConfig.fromJson(Map<String, dynamic> json) {
    final seconds = json['timeLimit'] as int?;
    return DailyChallengeModeConfig(
      challengeId: json['challengeId'] as String? ?? 'daily',
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      allowSaves: json['allowSave'] as bool? ?? false,
      timeLimitDuration: seconds != null ? Duration(seconds: seconds) : null,
      config: simulationConfigFromJson(
        json['config'] as Map<String, dynamic>?,
        fallback: defaultSimulationConfig,
      ),
      win: (json['winCondition'] as Map?) != null
          ? WinCondition.fromJson(
              Map<String, dynamic>.from(
                json['winCondition'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
      lose: (json['loseCondition'] as Map?) != null
          ? LoseCondition.fromJson(
              Map<String, dynamic>.from(
                json['loseCondition'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
    );
  }
}

ModeConfig modeConfigFromJson(Map<String, dynamic> json) {
  final modeName = json['mode'] as String? ?? GameMode.sandbox.name;
  final mode = GameMode.values.firstWhere(
    (value) => value.name == modeName,
    orElse: () => GameMode.sandbox,
  );
  switch (mode) {
    case GameMode.sandbox:
      return SandboxModeConfig.fromJson(json);
    case GameMode.zenMode:
      return ZenModeConfig.fromJson(json);
    case GameMode.campaign:
      return CampaignLevelConfig.fromJson(json);
    case GameMode.dailyChallenge:
      return DailyChallengeModeConfig.fromJson(json);
  }
}
