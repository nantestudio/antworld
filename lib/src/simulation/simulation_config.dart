import 'dart:math' as math;

class SimulationConfig {
  const SimulationConfig({
    this.cols = 100,
    this.rows = 75,
    this.cellSize = 8,
    this.startingAnts = 20,
    this.antSpeed = 48, // cells per second (~0.8 per frame @60fps)
    this.sensorDistance = 6,
    this.sensorAngle = 0.6,
    this.foodDepositStrength = 0.5,
    this.homeDepositStrength = 0.2,
    this.foodPickupRotation = math.pi,
    this.foodPerNewAnt = 3,
    this.nestRadius = 3,
    this.decayPerFrame = 0.985,
    this.decayThreshold = 0.01,
    this.digBrushRadius = 1,
    this.foodBrushRadius = 2,
    this.dirtMaxHealth = 100,
    this.digEnergyCost = 0.5,
    this.digDamagePerEnergy = 1,
    this.foodSenseRange = 30,
    this.energyCapacity = 100,
    this.energyDecayPerSecond = 0.4,
    this.energyRecoveryPerSecond = 4.0,
    this.restEnabled = true,
    this.explorerRatio = 0.05,
    this.randomTurnStrength = 1.2,
  });

  final int cols;
  final int rows;
  final double cellSize;
  final int startingAnts;
  final double antSpeed;
  final double sensorDistance;
  final double sensorAngle;
  final double foodDepositStrength;
  final double homeDepositStrength;
  final double foodPickupRotation;
  final int foodPerNewAnt;
  final int nestRadius;
  final double decayPerFrame;
  final double decayThreshold;
  final int digBrushRadius;
  final int foodBrushRadius;
  final double dirtMaxHealth;
  final double digEnergyCost;
  final double digDamagePerEnergy;
  final double foodSenseRange;
  final double energyCapacity;
  final double energyDecayPerSecond;
  final double energyRecoveryPerSecond;
  final bool restEnabled;
  final double explorerRatio;
  final double randomTurnStrength;

  double get decayPerSecond => math.pow(decayPerFrame, 60).toDouble();
  double get worldWidth => cols * cellSize;
  double get worldHeight => rows * cellSize;

  SimulationConfig copyWith({
    int? cols,
    int? rows,
    double? cellSize,
    int? startingAnts,
    double? antSpeed,
    double? sensorDistance,
    double? sensorAngle,
    double? foodDepositStrength,
    double? homeDepositStrength,
    double? foodPickupRotation,
    int? foodPerNewAnt,
    int? nestRadius,
    double? decayPerFrame,
    double? decayThreshold,
    int? digBrushRadius,
    int? foodBrushRadius,
    double? dirtMaxHealth,
    double? digEnergyCost,
    double? digDamagePerEnergy,
    double? foodSenseRange,
    double? energyCapacity,
    double? energyDecayPerSecond,
    double? energyRecoveryPerSecond,
    bool? restEnabled,
    double? explorerRatio,
    double? randomTurnStrength,
  }) {
    return SimulationConfig(
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      cellSize: cellSize ?? this.cellSize,
      startingAnts: startingAnts ?? this.startingAnts,
      antSpeed: antSpeed ?? this.antSpeed,
      sensorDistance: sensorDistance ?? this.sensorDistance,
      sensorAngle: sensorAngle ?? this.sensorAngle,
      foodDepositStrength: foodDepositStrength ?? this.foodDepositStrength,
      homeDepositStrength: homeDepositStrength ?? this.homeDepositStrength,
      foodPickupRotation: foodPickupRotation ?? this.foodPickupRotation,
      foodPerNewAnt: foodPerNewAnt ?? this.foodPerNewAnt,
      nestRadius: nestRadius ?? this.nestRadius,
      decayPerFrame: decayPerFrame ?? this.decayPerFrame,
      decayThreshold: decayThreshold ?? this.decayThreshold,
      digBrushRadius: digBrushRadius ?? this.digBrushRadius,
      foodBrushRadius: foodBrushRadius ?? this.foodBrushRadius,
      dirtMaxHealth: dirtMaxHealth ?? this.dirtMaxHealth,
      digEnergyCost: digEnergyCost ?? this.digEnergyCost,
      digDamagePerEnergy: digDamagePerEnergy ?? this.digDamagePerEnergy,
      foodSenseRange: foodSenseRange ?? this.foodSenseRange,
      energyCapacity: energyCapacity ?? this.energyCapacity,
      energyDecayPerSecond: energyDecayPerSecond ?? this.energyDecayPerSecond,
      energyRecoveryPerSecond:
          energyRecoveryPerSecond ?? this.energyRecoveryPerSecond,
      restEnabled: restEnabled ?? this.restEnabled,
      explorerRatio: explorerRatio ?? this.explorerRatio,
      randomTurnStrength: randomTurnStrength ?? this.randomTurnStrength,
    );
  }
}

const defaultSimulationConfig = SimulationConfig();
