import 'dart:math' as math;

class SimulationConfig {
  const SimulationConfig({
    this.cols = 100,
    this.rows = 75,
    this.cellSize = 8,
    this.startingAnts = 50,
    this.antSpeed = 48, // cells per second (~0.8 per frame @60fps)
    this.sensorDistance = 6,
    this.sensorAngle = 0.6,
    this.foodDepositStrength = 0.6,
    this.homeDepositStrength = 0.5,
    this.foodPickupRotation = math.pi,
    this.foodPerNewAnt = 3,
    this.nestRadius = 3,
    this.decayPerFrame = 0.985,
    this.decayThreshold = 0.01,
    this.digBrushRadius = 1,
    this.foodBrushRadius = 2,
    this.dirtMaxHealth = 20,
    this.digEnergyCost = 0.5,
    this.digDamagePerEnergy = 1,
    this.foodSenseRange = 150, // Large range for 400x400 maps
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

  double get decayPerSecond => math.pow(effectiveDecayPerFrame, 60).toDouble();
  double get worldWidth => cols * cellSize;
  double get worldHeight => rows * cellSize;

  /// Calculate decay rate based on map size so trails last long enough for round trips.
  /// Pheromones should persist for ~2-3x the time needed for a round trip across the map.
  double get effectiveDecayPerFrame {
    // Map diagonal in cells
    final diagonal = math.sqrt(cols * cols + rows * rows);
    // Round trip time in seconds (at antSpeed cells/sec)
    final roundTripTime = (2 * diagonal) / antSpeed;
    // Target persistence: 2.5x round trip time (minimum 15 seconds)
    final targetPersistence = math.max(15.0, roundTripTime * 2.5);
    // Calculate decay so pheromone at 0.5 stays above 0.01 for targetPersistence seconds
    // 0.5 * decay^(targetPersistence * 60) = 0.01
    // decay^(frames) = 0.02
    // decay = 0.02^(1/frames)
    final frames = targetPersistence * 60;
    final calculatedDecay = math.pow(0.02, 1 / frames);
    // Clamp to reasonable range
    return calculatedDecay.clamp(0.990, 0.9995).toDouble();
  }

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
