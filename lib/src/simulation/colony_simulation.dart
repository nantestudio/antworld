import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'ant.dart';
import 'simulation_config.dart';
import 'world_generator.dart';
import 'world_grid.dart';

class ColonySimulation {
  ColonySimulation(this.config)
    : antCount = ValueNotifier<int>(0),
      foodCollected = ValueNotifier<int>(0),
      pheromonesVisible = ValueNotifier<bool>(true),
      antSpeedMultiplier = ValueNotifier<double>(1.0),
      daysPassed = ValueNotifier<int>(1) {
    world = WorldGrid(config);
  }

  SimulationConfig config;
  late WorldGrid world;
  final List<Ant> ants = [];
  final ValueNotifier<int> antCount;
  final ValueNotifier<int> foodCollected;
  final ValueNotifier<bool> pheromonesVisible;
  final ValueNotifier<double> antSpeedMultiplier;
  final ValueNotifier<int> daysPassed;

  final math.Random _rng = math.Random();
  int _storedFood = 0;
  int _queuedAnts = 0;
  int? _lastSeed;
  double _elapsedTime = 0.0;

  bool get showPheromones => pheromonesVisible.value;
  int? get lastSeed => _lastSeed;

  void initialize() {
    world.reset();
    world.carveNest();
    ants.clear();
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
    foodCollected.value = 0;
    daysPassed.value = 1;

    for (var i = 0; i < config.startingAnts; i++) {
      _spawnAnt();
    }
    _updateAntCount();
  }

  void update(double dt) {
    final double clampedDt = dt.clamp(0.0, 0.05);
    final decayFactor = math.pow(config.decayPerSecond, clampedDt).toDouble();
    final double antSpeed = config.antSpeed * antSpeedMultiplier.value;
    world.decay(decayFactor, config.decayThreshold);

    // Track elapsed time and update days (1 minute = 1 day, affected by speed multiplier)
    _elapsedTime += clampedDt * antSpeedMultiplier.value;
    final newDays = (_elapsedTime / 60.0).floor() + 1;
    if (newDays != daysPassed.value) {
      daysPassed.value = newDays;
    }

    for (final ant in ants) {
      final delivered = ant.update(clampedDt, config, world, _rng, antSpeed);
      if (delivered) {
        _storedFood += 1;
        foodCollected.value = _storedFood;
        if (_storedFood % config.foodPerNewAnt == 0) {
          _queuedAnts += 1;
        }
      }
    }

    _flushSpawnQueue();
  }

  void togglePheromones() {
    pheromonesVisible.value = !pheromonesVisible.value;
  }

  void setPheromoneVisibility(bool visible) {
    pheromonesVisible.value = visible;
  }

  void setRestingEnabled(bool enabled) {
    if (config.restEnabled == enabled) {
      return;
    }
    config = config.copyWith(restEnabled: enabled);
    if (!enabled) {
      for (final ant in ants) {
        ant.exitRestState();
      }
    }
  }

  void dig(Vector2 cellPosition) {
    world.digCircle(cellPosition, config.digBrushRadius);
  }

  void placeFood(Vector2 cellPosition) {
    world.placeFood(cellPosition, config.foodBrushRadius);
  }

  void placeRock(Vector2 cellPosition) {
    world.placeRock(cellPosition, config.digBrushRadius);
  }

  void generateRandomWorld({int? seed}) {
    final generator = WorldGenerator();
    final actualSeed = seed ?? _rng.nextInt(0x7fffffff);
    final generated = generator.generate(baseConfig: config, seed: actualSeed);
    config = generated.config;
    world = generated.world;
    _lastSeed = actualSeed;
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
    foodCollected.value = 0;
    daysPassed.value = 1;
    ants.clear();
    for (var i = 0; i < config.startingAnts; i++) {
      _spawnAnt();
    }
    _updateAntCount();
  }

  Map<String, dynamic> toSnapshot() {
    return {
      'config': _configToJson(),
      'world': _worldToJson(),
      'ants': ants.map((ant) => ant.toJson()).toList(),
      'foodCollected': _storedFood,
      'antSpeedMultiplier': antSpeedMultiplier.value,
      'pheromonesVisible': pheromonesVisible.value,
      'seed': _lastSeed,
      'elapsedTime': _elapsedTime,
      'daysPassed': daysPassed.value,
    };
  }

  void restoreFromSnapshot(Map<String, dynamic> snapshot) {
    final configData = (snapshot['config'] as Map<String, dynamic>?) ?? {};
    config = _configFromJson(configData, config);

    final worldData = snapshot['world'] as Map<String, dynamic>?;
    final nestOverride = _vectorFromJson(
      worldData?['nest'] as Map<String, dynamic>?,
    );
    world = WorldGrid(config, nestOverride: nestOverride);
    if (worldData != null) {
      world.loadState(
        cellsData: _decodeUint8(worldData['cells'] as String),
        dirtHealthData: _decodeFloat32(worldData['dirtHealth'] as String),
        foodPheromoneData: _decodeFloat32(
          worldData['foodPheromones'] as String,
        ),
        homePheromoneData: _decodeFloat32(
          worldData['homePheromones'] as String,
        ),
      );
    }

    ants
      ..clear()
      ..addAll(
        ((snapshot['ants'] as List<dynamic>?) ?? []).map(
          (raw) => Ant.fromJson(Map<String, dynamic>.from(raw)),
        ),
      );
    _updateAntCount();

    _storedFood = (snapshot['foodCollected'] as num?)?.toInt() ?? 0;
    foodCollected.value = _storedFood;
    _queuedAnts = 0;
    antSpeedMultiplier.value =
        (snapshot['antSpeedMultiplier'] as num?)?.toDouble() ?? 1.0;
    pheromonesVisible.value = snapshot['pheromonesVisible'] as bool? ?? true;
    _lastSeed = (snapshot['seed'] as num?)?.toInt();
    _elapsedTime = (snapshot['elapsedTime'] as num?)?.toDouble() ?? 0.0;
    daysPassed.value = (snapshot['daysPassed'] as num?)?.toInt() ?? 0;
  }

  void addAnts(int count) {
    if (count <= 0) return;
    for (var i = 0; i < count; i++) {
      _spawnAnt();
    }
  }

  void removeAnts(int count) {
    if (count <= 0) return;
    final targetLength = math.max(1, ants.length - count);
    if (targetLength >= ants.length) return;
    ants.removeRange(targetLength, ants.length);
    _updateAntCount();
  }

  void scatterFood({int clusters = 6, int radius = 2}) {
    for (var i = 0; i < clusters; i++) {
      final gx = _rng.nextInt(world.cols);
      final gy = _rng.nextInt(world.rows);
      world.placeFood(Vector2(gx.toDouble(), gy.toDouble()), radius);
    }
  }

  void setAntSpeedMultiplier(double multiplier) {
    antSpeedMultiplier.value = multiplier.clamp(0.2, 5.0);
  }

  void resizeWorld({required int cols, required int rows}) {
    config = config.copyWith(cols: cols, rows: rows);
    world = WorldGrid(config);
    initialize();
    _lastSeed = null;
  }

  void _spawnAnt() {
    ants.add(
      Ant(
        startPosition: world.nestPosition,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
      ),
    );
    _updateAntCount();
  }

  void _flushSpawnQueue() {
    if (_queuedAnts == 0) {
      return;
    }
    for (var i = 0; i < _queuedAnts; i++) {
      _spawnAnt();
    }
    _queuedAnts = 0;
  }

  void _updateAntCount() {
    antCount.value = ants.length;
  }

  Map<String, dynamic> _configToJson() {
    return {
      'cols': config.cols,
      'rows': config.rows,
      'cellSize': config.cellSize,
      'startingAnts': config.startingAnts,
      'antSpeed': config.antSpeed,
      'sensorDistance': config.sensorDistance,
      'sensorAngle': config.sensorAngle,
      'foodDepositStrength': config.foodDepositStrength,
      'homeDepositStrength': config.homeDepositStrength,
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
    };
  }

  Map<String, dynamic> _worldToJson() {
    return {
      'cells': _encodeUint8(Uint8List.fromList(world.cells)),
      'dirtHealth': _encodeFloat32(world.dirtHealth),
      'foodPheromones': _encodeFloat32(world.foodPheromones),
      'homePheromones': _encodeFloat32(world.homePheromones),
      'nest': {'x': world.nestPosition.x, 'y': world.nestPosition.y},
    };
  }
}

SimulationConfig _configFromJson(
  Map<String, dynamic> data,
  SimulationConfig fallback,
) {
  return SimulationConfig(
    cols: (data['cols'] as num?)?.toInt() ?? fallback.cols,
    rows: (data['rows'] as num?)?.toInt() ?? fallback.rows,
    cellSize: (data['cellSize'] as num?)?.toDouble() ?? fallback.cellSize,
    startingAnts:
        (data['startingAnts'] as num?)?.toInt() ?? fallback.startingAnts,
    antSpeed: (data['antSpeed'] as num?)?.toDouble() ?? fallback.antSpeed,
    sensorDistance:
        (data['sensorDistance'] as num?)?.toDouble() ?? fallback.sensorDistance,
    sensorAngle:
        (data['sensorAngle'] as num?)?.toDouble() ?? fallback.sensorAngle,
    foodDepositStrength:
        (data['foodDepositStrength'] as num?)?.toDouble() ??
        fallback.foodDepositStrength,
    homeDepositStrength:
        (data['homeDepositStrength'] as num?)?.toDouble() ??
        fallback.homeDepositStrength,
    foodPickupRotation:
        (data['foodPickupRotation'] as num?)?.toDouble() ??
        fallback.foodPickupRotation,
    foodPerNewAnt:
        (data['foodPerNewAnt'] as num?)?.toInt() ?? fallback.foodPerNewAnt,
    nestRadius: (data['nestRadius'] as num?)?.toInt() ?? fallback.nestRadius,
    decayPerFrame:
        (data['decayPerFrame'] as num?)?.toDouble() ?? fallback.decayPerFrame,
    decayThreshold:
        (data['decayThreshold'] as num?)?.toDouble() ?? fallback.decayThreshold,
    digBrushRadius:
        (data['digBrushRadius'] as num?)?.toInt() ?? fallback.digBrushRadius,
    foodBrushRadius:
        (data['foodBrushRadius'] as num?)?.toInt() ?? fallback.foodBrushRadius,
    dirtMaxHealth:
        (data['dirtMaxHealth'] as num?)?.toDouble() ?? fallback.dirtMaxHealth,
    digEnergyCost:
        (data['digEnergyCost'] as num?)?.toDouble() ?? fallback.digEnergyCost,
    digDamagePerEnergy:
        (data['digDamagePerEnergy'] as num?)?.toDouble() ??
        fallback.digDamagePerEnergy,
    foodSenseRange:
        (data['foodSenseRange'] as num?)?.toDouble() ?? fallback.foodSenseRange,
    energyCapacity:
        (data['energyCapacity'] as num?)?.toDouble() ?? fallback.energyCapacity,
    energyDecayPerSecond:
        (data['energyDecayPerSecond'] as num?)?.toDouble() ??
        fallback.energyDecayPerSecond,
    energyRecoveryPerSecond:
        (data['energyRecoveryPerSecond'] as num?)?.toDouble() ??
        fallback.energyRecoveryPerSecond,
    restEnabled: data['restEnabled'] as bool? ?? fallback.restEnabled,
  );
}

String _encodeUint8(Uint8List data) => base64Encode(data);

Uint8List _decodeUint8(String data) => base64Decode(data);

String _encodeFloat32(Float32List data) {
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return base64Encode(bytes);
}

Float32List _decodeFloat32(String data) {
  final bytes = base64Decode(data);
  return bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}

Vector2? _vectorFromJson(Map<String, dynamic>? data) {
  if (data == null) {
    return null;
  }
  final dx = data['x'];
  final dy = data['y'];
  if (dx is num && dy is num) {
    return Vector2(dx.toDouble(), dy.toDouble());
  }
  return null;
}
