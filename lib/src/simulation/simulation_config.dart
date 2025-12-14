import 'dart:math' as math;

class SimulationConfig {
  const SimulationConfig({
    this.cols = 160,
    this.rows = 90,
    this.cellSize = 8,
    this.colonyCount = 2,
    this.startingAnts = 80,
    this.antSpeed =
        30, // cells per second - slower for more deliberate movement
    this.sensorDistance = 8, // longer sensing reach
    this.sensorAngle = 0.52, // ~30° tighter cone for focused trails
    this.foodDepositStrength = 0.4, // reduced to prevent pheromone saturation
    this.homeDepositStrength = 0.35, // balanced with food deposit
    this.trailDepositStrength = 0.12, // ALL ants deposit this as they walk
    this.trailSenseWeight = 2.5, // How much trail pheromone influences steering
    this.minTrailToDig = 0.25, // Don't dig if trail pheromone > this (prevents widening)
    this.foodPickupRotation = math.pi,
    this.foodPerNewAnt = 10, // slower colony growth
    this.nestRadius = 3,
    this.decayPerFrame = 0.985,
    this.decayThreshold = 0.01,
    this.digBrushRadius = 1,
    this.foodBrushRadius = 2,
    this.dirtMaxHealth = 20,
    this.digEnergyCost = 0.8, // digging costs more energy
    this.digDamagePerEnergy = 1,
    this.foodSenseRange = 150, // Large range for 400x400 maps
    this.energyCapacity = 80, // reduced capacity
    this.energyDecayPerSecond = 0.6, // faster energy drain
    this.energyRecoveryPerSecond = 3.0, // slower recovery
    this.restEnabled = true,
    this.explorerRatio = 0.05,
    this.randomTurnStrength = 1.2,
  });

  final int cols;
  final int rows;
  final double cellSize;
  final int colonyCount; // 1-4 colonies
  final int startingAnts;
  final double antSpeed;
  final double sensorDistance;
  final double sensorAngle;
  final double foodDepositStrength;
  final double homeDepositStrength;
  final double trailDepositStrength;
  final double trailSenseWeight;
  final double minTrailToDig;
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
    int? colonyCount,
    int? startingAnts,
    double? antSpeed,
    double? sensorDistance,
    double? sensorAngle,
    double? foodDepositStrength,
    double? homeDepositStrength,
    double? trailDepositStrength,
    double? trailSenseWeight,
    double? minTrailToDig,
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
      colonyCount: colonyCount ?? this.colonyCount,
      startingAnts: startingAnts ?? this.startingAnts,
      antSpeed: antSpeed ?? this.antSpeed,
      sensorDistance: sensorDistance ?? this.sensorDistance,
      sensorAngle: sensorAngle ?? this.sensorAngle,
      foodDepositStrength: foodDepositStrength ?? this.foodDepositStrength,
      homeDepositStrength: homeDepositStrength ?? this.homeDepositStrength,
      trailDepositStrength: trailDepositStrength ?? this.trailDepositStrength,
      trailSenseWeight: trailSenseWeight ?? this.trailSenseWeight,
      minTrailToDig: minTrailToDig ?? this.minTrailToDig,
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

Map<String, dynamic> simulationConfigToJson(SimulationConfig config) {
  return {
    'cols': config.cols,
    'rows': config.rows,
    'cellSize': config.cellSize,
    'colonyCount': config.colonyCount,
    'startingAnts': config.startingAnts,
    'antSpeed': config.antSpeed,
    'sensorDistance': config.sensorDistance,
    'sensorAngle': config.sensorAngle,
    'foodDepositStrength': config.foodDepositStrength,
    'homeDepositStrength': config.homeDepositStrength,
    'trailDepositStrength': config.trailDepositStrength,
    'trailSenseWeight': config.trailSenseWeight,
    'minTrailToDig': config.minTrailToDig,
    'foodPickupRotation': config.foodPickupRotation,
    'foodPerNewAnt': config.foodPerNewAnt,
    'nestRadius': config.nestRadius,
    'decayPerFrame': config.decayPerFrame,
    'decayThreshold': config.decayThreshold,
    'digBrushRadius': config.digBrushRadius,
    'foodBrushRadius': config.foodBrushRadius,
    'dirtMaxHealth': config.dirtMaxHealth,
    'digEnergyCost': config.digEnergyCost,
    'digDamagePerEnergy': config.digDamagePerEnergy,
    'foodSenseRange': config.foodSenseRange,
    'energyCapacity': config.energyCapacity,
    'energyDecayPerSecond': config.energyDecayPerSecond,
    'energyRecoveryPerSecond': config.energyRecoveryPerSecond,
    'restEnabled': config.restEnabled,
    'explorerRatio': config.explorerRatio,
    'randomTurnStrength': config.randomTurnStrength,
  };
}

SimulationConfig simulationConfigFromJson(
  Map<String, dynamic>? data, {
  SimulationConfig? fallback,
}) {
  final base = fallback ?? defaultSimulationConfig;
  if (data == null) {
    return base;
  }
  return SimulationConfig(
    cols: (data['cols'] as num?)?.toInt() ?? base.cols,
    rows: (data['rows'] as num?)?.toInt() ?? base.rows,
    cellSize: (data['cellSize'] as num?)?.toDouble() ?? base.cellSize,
    colonyCount: (data['colonyCount'] as num?)?.toInt() ?? base.colonyCount,
    startingAnts: (data['startingAnts'] as num?)?.toInt() ?? base.startingAnts,
    antSpeed: (data['antSpeed'] as num?)?.toDouble() ?? base.antSpeed,
    sensorDistance:
        (data['sensorDistance'] as num?)?.toDouble() ?? base.sensorDistance,
    sensorAngle: (data['sensorAngle'] as num?)?.toDouble() ?? base.sensorAngle,
    foodDepositStrength:
        (data['foodDepositStrength'] as num?)?.toDouble() ??
            base.foodDepositStrength,
    homeDepositStrength:
        (data['homeDepositStrength'] as num?)?.toDouble() ??
            base.homeDepositStrength,
    trailDepositStrength:
        (data['trailDepositStrength'] as num?)?.toDouble() ??
            base.trailDepositStrength,
    trailSenseWeight:
        (data['trailSenseWeight'] as num?)?.toDouble() ?? base.trailSenseWeight,
    minTrailToDig:
        (data['minTrailToDig'] as num?)?.toDouble() ?? base.minTrailToDig,
    foodPickupRotation:
        (data['foodPickupRotation'] as num?)?.toDouble() ??
            base.foodPickupRotation,
    foodPerNewAnt:
        (data['foodPerNewAnt'] as num?)?.toInt() ?? base.foodPerNewAnt,
    nestRadius: (data['nestRadius'] as num?)?.toInt() ?? base.nestRadius,
    decayPerFrame:
        (data['decayPerFrame'] as num?)?.toDouble() ?? base.decayPerFrame,
    decayThreshold:
        (data['decayThreshold'] as num?)?.toDouble() ?? base.decayThreshold,
    digBrushRadius:
        (data['digBrushRadius'] as num?)?.toInt() ?? base.digBrushRadius,
    foodBrushRadius:
        (data['foodBrushRadius'] as num?)?.toInt() ?? base.foodBrushRadius,
    dirtMaxHealth:
        (data['dirtMaxHealth'] as num?)?.toDouble() ?? base.dirtMaxHealth,
    digEnergyCost:
        (data['digEnergyCost'] as num?)?.toDouble() ?? base.digEnergyCost,
    digDamagePerEnergy:
        (data['digDamagePerEnergy'] as num?)?.toDouble() ??
        base.digDamagePerEnergy,
    foodSenseRange:
        (data['foodSenseRange'] as num?)?.toDouble() ?? base.foodSenseRange,
    energyCapacity:
        (data['energyCapacity'] as num?)?.toDouble() ?? base.energyCapacity,
    energyDecayPerSecond:
        (data['energyDecayPerSecond'] as num?)?.toDouble() ??
        base.energyDecayPerSecond,
    energyRecoveryPerSecond:
        (data['energyRecoveryPerSecond'] as num?)?.toDouble() ??
        base.energyRecoveryPerSecond,
    restEnabled: (data['restEnabled'] as bool?) ?? base.restEnabled,
    explorerRatio:
        (data['explorerRatio'] as num?)?.toDouble() ?? base.explorerRatio,
    randomTurnStrength:
        (data['randomTurnStrength'] as num?)?.toDouble() ??
        base.randomTurnStrength,
  );
}
