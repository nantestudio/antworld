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
      antSpeedMultiplier = ValueNotifier<double>(0.2),
      daysPassed = ValueNotifier<int>(1) {
    world = WorldGrid(config);
  }

  SimulationConfig config;
  late WorldGrid world;
  final List<Ant> ants = [];
  final List<Ant> enemyAnts = [];
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
  double _raidTimer = 0.0;
  double _nextRaidIn = 45.0;
  double _foodCheckTimer = 0.0;
  double _nextFoodCheck = 20.0;

  bool get showPheromones => pheromonesVisible.value;
  int? get lastSeed => _lastSeed;

  void initialize() {
    world.reset();
    world.carveNest();
    ants.clear();
    enemyAnts.clear();
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
    _scheduleNextRaid();
    _scheduleNextFoodCheck();
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
      final delivered =
          ant.update(clampedDt, config, world, _rng, antSpeed, attackTarget: null);
      if (delivered) {
        _storedFood += 1;
        foodCollected.value = _storedFood;
        if (_storedFood % config.foodPerNewAnt == 0) {
          _queuedAnts += 1;
        }
      }
    }

    final double enemySpeed = antSpeed * 0.9;
    for (final enemy in enemyAnts) {
      final target = _enemyTargetFor(enemy);
      enemy.update(
        clampedDt,
        config,
        world,
        _rng,
        enemySpeed,
        attackTarget: target,
      );
    }

    _applySeparation();
    _resolveCombat();
    _removeStuckAnts();
    _flushSpawnQueue();

    _raidTimer += clampedDt;
    if (_raidTimer >= _nextRaidIn && ants.isNotEmpty) {
      _spawnEnemyRaid();
      _scheduleNextRaid();
    }
    _foodCheckTimer += clampedDt;
    if (_foodCheckTimer >= _nextFoodCheck) {
      _maintainFoodSupply();
      _scheduleNextFoodCheck();
    }
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

  void setExplorerRatio(double ratio) {
    final clamped = ratio.clamp(0.0, 0.6).toDouble();
    config = config.copyWith(explorerRatio: clamped);
  }

  void setRandomTurnStrength(double value) {
    final clamped = value.clamp(0.2, 3.0).toDouble();
    config = config.copyWith(randomTurnStrength: clamped);
  }

  void setSensorDistance(double value) {
    final clamped = value.clamp(2.0, 20.0).toDouble();
    config = config.copyWith(sensorDistance: clamped);
  }

  void setSensorAngle(double value) {
    final clamped = value.clamp(0.1, 1.5).toDouble();
    config = config.copyWith(sensorAngle: clamped);
  }

  void setFoodDepositStrength(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    config = config.copyWith(foodDepositStrength: clamped);
  }

  void setHomeDepositStrength(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    config = config.copyWith(homeDepositStrength: clamped);
  }

  void setDecayPerFrame(double value) {
    final clamped = value.clamp(0.80, 0.9999).toDouble();
    config = config.copyWith(decayPerFrame: clamped);
  }

  void setDecayThreshold(double value) {
    final clamped = value.clamp(0.0, 0.2).toDouble();
    config = config.copyWith(decayThreshold: clamped);
  }

  void setEnergyCapacity(double value) {
    final clamped = value.clamp(20.0, 400.0).toDouble();
    config = config.copyWith(energyCapacity: clamped);
  }

  void setEnergyDecayRate(double value) {
    final clamped = value.clamp(0.0, 5.0).toDouble();
    config = config.copyWith(energyDecayPerSecond: clamped);
  }

  void setEnergyRecoveryRate(double value) {
    final clamped = value.clamp(0.0, 5.0).toDouble();
    config = config.copyWith(energyRecoveryPerSecond: clamped);
  }

  void setFoodSenseRange(double value) {
    final clamped = value.clamp(5.0, 100.0).toDouble();
    config = config.copyWith(foodSenseRange: clamped);
  }

  void resetBehaviorDefaults() {
    config = defaultSimulationConfig.copyWith(
      cols: config.cols,
      rows: config.rows,
      cellSize: config.cellSize,
      startingAnts: config.startingAnts,
    );
  }

  void spawnDebugRaid() {
    _spawnEnemyRaid();
    _scheduleNextRaid();
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

  /// Prepares the simulation for a new world by clearing all state.
  /// Call this before generating a new world to free up resources.
  void prepareForNewWorld() {
    ants.clear();
    enemyAnts.clear();
    _updateAntCount();
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
    _scheduleNextRaid();
    _scheduleNextFoodCheck();
    foodCollected.value = 0;
    daysPassed.value = 1;
    // Replace world with minimal placeholder to free memory from old arrays
    final minConfig = config.copyWith(cols: 2, rows: 2);
    world = WorldGrid(minConfig);
  }

  /// Applies a generated world to the simulation.
  void applyGeneratedWorld(GeneratedWorld generated) {
    config = generated.config;
    world = generated.world;
    _lastSeed = generated.seed;
    enemyAnts.clear();
    _scheduleNextRaid();
    _scheduleNextFoodCheck();
    for (var i = 0; i < config.startingAnts; i++) {
      _spawnAnt();
    }
    _updateAntCount();
  }

  void generateRandomWorld({int? seed}) {
    // Clean up first to free resources
    prepareForNewWorld();

    final generator = WorldGenerator();
    final actualSeed = seed ?? _rng.nextInt(0x7fffffff);
    final generated = generator.generate(baseConfig: config, seed: actualSeed);
    applyGeneratedWorld(generated);
  }

  Map<String, dynamic> toSnapshot() {
    return {
      'config': _configToJson(),
      'world': _worldToJson(),
      'ants': ants.map((ant) => ant.toJson()).toList(),
      'enemyAnts': enemyAnts.map((ant) => ant.toJson()).toList(),
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

    enemyAnts
      ..clear()
      ..addAll(
        ((snapshot['enemyAnts'] as List<dynamic>?) ?? []).map(
          (raw) => Ant.fromJson(Map<String, dynamic>.from(raw)),
        ),
      );

    _storedFood = (snapshot['foodCollected'] as num?)?.toInt() ?? 0;
    foodCollected.value = _storedFood;
    _queuedAnts = 0;
    antSpeedMultiplier.value =
        (snapshot['antSpeedMultiplier'] as num?)?.toDouble() ?? 0.2;
    pheromonesVisible.value = snapshot['pheromonesVisible'] as bool? ?? true;
    _lastSeed = (snapshot['seed'] as num?)?.toInt();
    _elapsedTime = (snapshot['elapsedTime'] as num?)?.toDouble() ?? 0.0;
    daysPassed.value = (snapshot['daysPassed'] as num?)?.toInt() ?? 0;
    _scheduleNextRaid();
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
    final stats = _rollFriendlyStats();
    ants.add(
      Ant(
        startPosition: world.nestPosition,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        explorerRatio: config.explorerRatio,
        attack: stats.attack,
        defense: stats.defense,
        maxHpValue: stats.hp,
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

  void _scheduleNextRaid() {
    _raidTimer = 0;
    _nextRaidIn = 35 + _rng.nextDouble() * 40;
  }

  void _scheduleNextFoodCheck() {
    _foodCheckTimer = 0;
    _nextFoodCheck = 12 + _rng.nextDouble() * 10;
  }

  void _spawnEnemyRaid() {
    if (ants.isEmpty) {
      return;
    }
    final ratio = 0.01 + _rng.nextDouble() * 0.19;
    final desired = math.max(1, (ants.length * ratio).round());
    final spawnPoint = _pickRaidSpawnPoint();
    world.digCircle(spawnPoint, 3);
    for (var i = 0; i < desired; i++) {
      final offset = Vector2(
        ( _rng.nextDouble() - 0.5) * 2,
        ( _rng.nextDouble() - 0.5) * 2,
      );
      final spawnPos = Vector2(
        (spawnPoint.x + offset.x).clamp(1, world.cols - 2),
        (spawnPoint.y + offset.y).clamp(1, world.rows - 2),
      );
      final stats = _rollEnemyStats();
      enemyAnts.add(
        Ant(
          startPosition: spawnPos,
          angle: _rng.nextDouble() * math.pi * 2,
          energy: config.energyCapacity,
          rng: _rng,
          explorerRatio: 0,
          attack: stats.attack,
          defense: stats.defense,
          maxHpValue: stats.hp,
          isEnemy: true,
        ),
      );
    }
  }

  void _maintainFoodSupply() {
    final current = world.foodCount;
    final area = world.cols * world.rows;
    final baseline = math.max(80, (area * 0.012).round());
    final antTarget = ants.length * 4;
    final target = math.max(baseline, antTarget);
    if (current >= target) {
      return;
    }
    final deficit = target - current;
    final clusters = math.min(6, math.max(1, (deficit / 25).ceil()));
    for (var i = 0; i < clusters; i++) {
      final spot = _randomOpenCell();
      if (spot == null) {
        break;
      }
      final radius = 2 + _rng.nextInt(3);
      world.placeFood(spot, radius);
    }
  }

  void _applySeparation() {
    const double minSpacing = 0.45;
    final Map<int, List<Ant>> occupancy = {};
    void addGroup(List<Ant> group) {
      for (final ant in group) {
        if (ant.isDead) continue;
        final gx = ant.position.x.floor();
        final gy = ant.position.y.floor();
        if (!world.isInsideIndex(gx, gy)) {
          continue;
        }
        final key = world.index(gx, gy);
        occupancy.putIfAbsent(key, () => []).add(ant);
      }
    }

    addGroup(ants);
    addGroup(enemyAnts);
    if (occupancy.isEmpty) {
      return;
    }

    final Map<Ant, Vector2> adjustments = {};
    for (final entry in occupancy.entries) {
      final occupants = entry.value;
      if (occupants.length < 2) {
        continue;
      }
      for (var i = 0; i < occupants.length; i++) {
        for (var j = i + 1; j < occupants.length; j++) {
          final a = occupants[i];
          final b = occupants[j];
          final dx = a.position.x - b.position.x;
          final dy = a.position.y - b.position.y;
          var distSq = dx * dx + dy * dy;
          if (distSq < 1e-4) {
            final jitter = _rng.nextDouble() * 0.1 + 0.05;
            final angle = _rng.nextDouble() * math.pi * 2;
            final pushX = math.cos(angle) * jitter;
            final pushY = math.sin(angle) * jitter;
            _accumulateAdjustment(adjustments, a, pushX, pushY);
            _accumulateAdjustment(adjustments, b, -pushX, -pushY);
            continue;
          }
          final dist = math.sqrt(distSq);
          final overlap = minSpacing - dist;
          if (overlap <= 0) {
            continue;
          }
          final push = overlap * 0.5;
          final invDist = 1 / dist;
          final pushX = dx * invDist * push;
          final pushY = dy * invDist * push;
          _accumulateAdjustment(adjustments, a, pushX, pushY);
          _accumulateAdjustment(adjustments, b, -pushX, -pushY);
        }
      }
    }

    for (final entry in adjustments.entries) {
      final ant = entry.key;
      final delta = entry.value;
      final newX = (ant.position.x + delta.x).clamp(1.0, world.cols - 2.0);
      final newY = (ant.position.y + delta.y).clamp(1.0, world.rows - 2.0);
      ant.position.setValues(newX.toDouble(), newY.toDouble());
    }
  }

  void _accumulateAdjustment(
    Map<Ant, Vector2> adjustments,
    Ant ant,
    double dx,
    double dy,
  ) {
    final existing = adjustments[ant];
    if (existing != null) {
      existing.x += dx;
      existing.y += dy;
    } else {
      adjustments[ant] = Vector2(dx, dy);
    }
  }

  Vector2 _pickRaidSpawnPoint() {
    final edge = _rng.nextInt(4);
    final cols = world.cols;
    final rows = world.rows;
    switch (edge) {
      case 0: // Top
        return Vector2(_rng.nextInt(cols - 4).toDouble() + 2, 1);
      case 1: // Bottom
        return Vector2(_rng.nextInt(cols - 4).toDouble() + 2, rows - 2);
      case 2: // Left
        return Vector2(1, _rng.nextInt(rows - 4).toDouble() + 2);
      default: // Right
        return Vector2(cols - 2, _rng.nextInt(rows - 4).toDouble() + 2);
    }
  }

  Vector2? _randomOpenCell() {
    if (world.cols < 4 || world.rows < 4) {
      return null;
    }
    for (var attempt = 0; attempt < 40; attempt++) {
      final x = _rng.nextInt(world.cols - 4) + 2;
      final y = _rng.nextInt(world.rows - 4) + 2;
      if (world.cellTypeAt(x, y) == CellType.air) {
        return Vector2(x.toDouble(), y.toDouble());
      }
    }
    return null;
  }

  void _resolveCombat() {
    const double fightRadius = 0.6;
    const double fightRadiusSq = fightRadius * fightRadius;
    final deadFriendlies = <Ant>{};
    final deadEnemies = <Ant>{};

    for (final enemy in enemyAnts) {
      if (enemy.isDead) {
        deadEnemies.add(enemy);
        continue;
      }
      for (final ally in ants) {
        if (ally.isDead) {
          deadFriendlies.add(ally);
          continue;
        }
        final distSq = ally.position.distanceToSquared(enemy.position);
        if (distSq <= fightRadiusSq) {
          final damageToAlly = _computeDamage(enemy, ally);
          ally.applyDamage(damageToAlly);
          final damageToEnemy = _computeDamage(ally, enemy);
          enemy.applyDamage(damageToEnemy);
          if (ally.isDead) {
            deadFriendlies.add(ally);
          }
          if (enemy.isDead) {
            deadEnemies.add(enemy);
            break;
          }
        }
      }
    }

    if (deadFriendlies.isNotEmpty) {
      ants.removeWhere(deadFriendlies.contains);
      _updateAntCount();
    }
    if (deadEnemies.isNotEmpty) {
      enemyAnts.removeWhere(deadEnemies.contains);
    }
  }

  void _removeStuckAnts() {
    final stuckFriendlies = ants.where((a) => a.isStuck).toList();
    final stuckEnemies = enemyAnts.where((a) => a.isStuck).toList();

    if (stuckFriendlies.isNotEmpty) {
      ants.removeWhere(stuckFriendlies.contains);
      _updateAntCount();
    }
    if (stuckEnemies.isNotEmpty) {
      enemyAnts.removeWhere(stuckEnemies.contains);
    }
  }

  double _computeDamage(Ant attacker, Ant defender) {
    final variance = 0.8 + _rng.nextDouble() * 0.5;
    final mitigation = defender.defense * (0.3 + _rng.nextDouble() * 0.2);
    return math.max(0.2, attacker.attack * variance - mitigation);
  }

  Vector2? _enemyTargetFor(Ant enemy) {
    Ant? closest;
    double bestDist = double.infinity;
    for (final ally in ants) {
      final dist = ally.position.distanceToSquared(enemy.position);
      if (dist < bestDist) {
        bestDist = dist;
        closest = ally;
      }
    }
    return closest?.position ?? world.nestPosition;
  }

  _CombatStats _rollFriendlyStats() {
    final hp = 80 + _rng.nextDouble() * 40;
    final attack = 4 + _rng.nextDouble() * 3;
    final defense = 1 + _rng.nextDouble() * 2;
    return _CombatStats(hp: hp, attack: attack, defense: defense);
  }

  _CombatStats _rollEnemyStats() {
    final hp = 70 + _rng.nextDouble() * 60;
    final attack = 5 + _rng.nextDouble() * 4;
    final defense = 1 + _rng.nextDouble() * 3;
    return _CombatStats(hp: hp, attack: attack, defense: defense);
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
      'explorerRatio': config.explorerRatio,
      'randomTurnStrength': config.randomTurnStrength,
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
    explorerRatio:
        (data['explorerRatio'] as num?)?.toDouble() ?? fallback.explorerRatio,
    randomTurnStrength:
        (data['randomTurnStrength'] as num?)?.toDouble() ??
        fallback.randomTurnStrength,
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

class _CombatStats {
  const _CombatStats({required this.hp, required this.attack, required this.defense});
  final double hp;
  final double attack;
  final double defense;
}
