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
      daysPassed = ValueNotifier<int>(1),
      elapsedTime = ValueNotifier<double>(0.0) {
    world = WorldGrid(config);
  }

  SimulationConfig config;
  late WorldGrid world;
  final List<Ant> ants = []; // Contains ants from all colonies
  final ValueNotifier<int> antCount;
  final ValueNotifier<int> foodCollected;
  final ValueNotifier<bool> pheromonesVisible;
  final ValueNotifier<double> antSpeedMultiplier;
  final ValueNotifier<int> daysPassed;
  final ValueNotifier<double> elapsedTime;

  final math.Random _rng = math.Random();
  int _storedFood = 0;
  int _queuedAnts = 0;
  int? _lastSeed;
  double _elapsedTime = 0.0;
  double _foodCheckTimer = 0.0;
  double _nextFoodCheck = 300.0; // ~5 minutes between food spawns

  bool get showPheromones => pheromonesVisible.value;
  int? get lastSeed => _lastSeed;

  // Stats getters for UI - colony 0 is "our" colony for display purposes
  int get enemyCount => ants.where((a) => a.colonyId != 0).length;
  int get restingCount => ants.where((a) => a.colonyId == 0 && a.state == AntState.rest).length;
  int get carryingFoodCount => ants.where((a) => a.colonyId == 0 && a.hasFood).length;
  int get foragingCount => ants.where((a) => a.colonyId == 0 && a.state == AntState.forage && !a.hasFood).length;
  int get workerCount => ants.where((a) => a.colonyId == 0 && a.caste == AntCaste.worker).length;
  int get soldierCount => ants.where((a) => a.colonyId == 0 && a.caste == AntCaste.soldier).length;
  int get nurseCount => ants.where((a) => a.colonyId == 0 && a.caste == AntCaste.nurse).length;
  int get larvaCount => ants.where((a) => a.colonyId == 0 && a.caste == AntCaste.larva).length;
  int get queenCount => ants.where((a) => a.colonyId == 0 && a.caste == AntCaste.queen).length;

  // Colony 1 stats
  int get enemy1WorkerCount => ants.where((a) => a.colonyId == 1 && a.caste == AntCaste.worker).length;
  int get enemy1SoldierCount => ants.where((a) => a.colonyId == 1 && a.caste == AntCaste.soldier).length;
  int get enemy1NurseCount => ants.where((a) => a.colonyId == 1 && a.caste == AntCaste.nurse).length;
  int get enemy1LarvaCount => ants.where((a) => a.colonyId == 1 && a.caste == AntCaste.larva).length;
  int get enemy1QueenCount => ants.where((a) => a.colonyId == 1 && a.caste == AntCaste.queen).length;

  void initialize() {
    world.reset();
    world.carveNest();
    ants.clear();
    Ant.resetIdCounter();
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
    elapsedTime.value = 0.0;
    _scheduleNextFoodCheck();
    foodCollected.value = 0;
    daysPassed.value = 1;

    _spawnInitialColony();
    _updateAntCount();
  }

  void _spawnInitialColony() {
    // Spawn ants for both colonies
    for (var colonyId = 0; colonyId < 2; colonyId++) {
      // Always spawn one queen
      _spawnAnt(caste: AntCaste.queen, colonyId: colonyId);

      // Calculate base counts with ±20% variance
      final baseNurse = config.startingAnts * 0.15; // ~15% nurses
      final baseSoldier = config.startingAnts * 0.20; // ~20% soldiers

      // Add randomness: base * (0.8 to 1.2)
      final nurseCount = math.max(2, (baseNurse * (0.8 + _rng.nextDouble() * 0.4)).round());
      final soldierCount = math.max(2, (baseSoldier * (0.8 + _rng.nextDouble() * 0.4)).round());

      // Spawn nurses
      for (var i = 0; i < nurseCount; i++) {
        _spawnAnt(caste: AntCaste.nurse, colonyId: colonyId);
      }

      // Spawn soldiers
      for (var i = 0; i < soldierCount; i++) {
        _spawnAnt(caste: AntCaste.soldier, colonyId: colonyId);
      }

      // Rest are workers (~65%)
      final workerCount = config.startingAnts - 1 - nurseCount - soldierCount;
      for (var i = 0; i < workerCount; i++) {
        _spawnAnt(caste: AntCaste.worker, colonyId: colonyId);
      }
    }
  }

  void update(double dt) {
    final double clampedDt = dt.clamp(0.0, 0.05);
    final decayFactor = math.pow(config.decayPerSecond, clampedDt).toDouble();
    final double antSpeed = config.antSpeed * antSpeedMultiplier.value;
    world.decay(decayFactor, config.decayThreshold);

    // Track elapsed time and update days (1 minute = 1 day, affected by speed multiplier)
    _elapsedTime += clampedDt * antSpeedMultiplier.value;
    elapsedTime.value = _elapsedTime;
    final newDays = (_elapsedTime / 60.0).floor() + 1;
    if (newDays != daysPassed.value) {
      daysPassed.value = newDays;
    }

    final larvaeToMature = <Ant>[];
    final queensLayingEggs = <Ant>[];
    for (final ant in ants) {
      final result =
          ant.update(clampedDt, config, world, _rng, antSpeed, attackTarget: null);

      if (ant.caste == AntCaste.queen && result) {
        // Queen wants to lay an egg - defer spawning until after iteration
        queensLayingEggs.add(ant);
      } else if (ant.caste == AntCaste.larva && ant.isReadyToMature) {
        // Larva ready to become a worker
        larvaeToMature.add(ant);
      } else if (result && ant.caste == AntCaste.worker) {
        // Worker delivered food
        _storedFood += 1;
        foodCollected.value = _storedFood;
        if (_storedFood % config.foodPerNewAnt == 0) {
          _queuedAnts += 1;
        }
      }
    }

    // Spawn larvae from queens (after iteration to avoid concurrent modification)
    for (final queen in queensLayingEggs) {
      _spawnLarvaAtQueen(queen);
    }

    // Mature larvae into workers
    for (final larva in larvaeToMature) {
      _matureLarva(larva);
    }

    _applySeparation();
    _resolveCombat();
    _removeStuckAnts();
    _flushSpawnQueue();

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
    Ant.resetIdCounter();
    _updateAntCount();
    _storedFood = 0;
    _queuedAnts = 0;
    _elapsedTime = 0.0;
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
    _scheduleNextFoodCheck();
    _spawnInitialColony();
    _updateAntCount();
  }

  void generateRandomWorld({int? seed, int? cols, int? rows}) {
    // Clean up first to free resources
    prepareForNewWorld();

    final generator = WorldGenerator();
    final actualSeed = seed ?? _rng.nextInt(0x7fffffff);
    final generated = generator.generate(
      baseConfig: config,
      seed: actualSeed,
      cols: cols,
      rows: rows,
    );
    applyGeneratedWorld(generated);
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
    final nest1Override = _vectorFromJson(
      worldData?['nest1'] as Map<String, dynamic>?,
    );
    world = WorldGrid(config, nestOverride: nestOverride, nest1Override: nest1Override);
    if (worldData != null) {
      final zonesStr = worldData['zones'] as String?;
      final blockedStr = worldData['blockedPheromones'] as String?;
      final foodAmountStr = worldData['foodAmount'] as String?;

      // Support both legacy (single layer) and new (per-colony) pheromone formats
      final legacyFoodStr = worldData['foodPheromones'] as String?;
      final legacyHomeStr = worldData['homePheromones'] as String?;
      final food0Str = worldData['foodPheromones0'] as String?;
      final food1Str = worldData['foodPheromones1'] as String?;
      final home0Str = worldData['homePheromones0'] as String?;
      final home1Str = worldData['homePheromones1'] as String?;

      world.loadState(
        cellsData: _decodeUint8(worldData['cells'] as String),
        dirtHealthData: _decodeFloat32(worldData['dirtHealth'] as String),
        // Legacy pheromone data (will be copied to colony 0 layer)
        foodPheromoneData: legacyFoodStr != null ? _decodeFloat32(legacyFoodStr) : null,
        homePheromoneData: legacyHomeStr != null ? _decodeFloat32(legacyHomeStr) : null,
        // Per-colony pheromone data
        foodPheromone0Data: food0Str != null ? _decodeFloat32(food0Str) : null,
        foodPheromone1Data: food1Str != null ? _decodeFloat32(food1Str) : null,
        homePheromone0Data: home0Str != null ? _decodeFloat32(home0Str) : null,
        homePheromone1Data: home1Str != null ? _decodeFloat32(home1Str) : null,
        zonesData: zonesStr != null ? _decodeUint8(zonesStr) : null,
        blockedPheromoneData: blockedStr != null ? _decodeFloat32(blockedStr) : null,
        foodAmountData: foodAmountStr != null ? _decodeUint8(foodAmountStr) : null,
      );
    }

    ants
      ..clear()
      ..addAll(
        ((snapshot['ants'] as List<dynamic>?) ?? []).map(
          (raw) => Ant.fromJson(Map<String, dynamic>.from(raw)),
        ),
      );
    // Migrate old enemy ants from previous saves
    final oldEnemyAnts = (snapshot['enemyAnts'] as List<dynamic>?) ?? [];
    for (final raw in oldEnemyAnts) {
      ants.add(Ant.fromJson(Map<String, dynamic>.from(raw)));
    }
    _updateAntCount();

    _storedFood = (snapshot['foodCollected'] as num?)?.toInt() ?? 0;
    foodCollected.value = _storedFood;
    _queuedAnts = 0;
    antSpeedMultiplier.value =
        (snapshot['antSpeedMultiplier'] as num?)?.toDouble() ?? 0.2;
    pheromonesVisible.value = snapshot['pheromonesVisible'] as bool? ?? true;
    _lastSeed = (snapshot['seed'] as num?)?.toInt();
    _elapsedTime = (snapshot['elapsedTime'] as num?)?.toDouble() ?? 0.0;
    daysPassed.value = (snapshot['daysPassed'] as num?)?.toInt() ?? 0;

    // Ensure both colonies have a queen (for migrating old saves)
    _ensureQueensExist();
  }

  /// Ensures both colonies have at least one queen
  void _ensureQueensExist() {
    for (var colonyId = 0; colonyId < 2; colonyId++) {
      final hasQueen = ants.any((a) => a.colonyId == colonyId && a.caste == AntCaste.queen);
      if (!hasQueen) {
        _spawnAnt(caste: AntCaste.queen, colonyId: colonyId);
      }
    }
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

  void _spawnAnt({AntCaste caste = AntCaste.worker, int colonyId = 0}) {
    ants.add(
      Ant(
        startPosition: world.getNestPosition(colonyId),
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: caste,
        colonyId: colonyId,
      ),
    );
    _updateAntCount();
  }

  void _spawnLarvaAtQueen(Ant queen) {
    // Spawn larva near the queen's position (in queen chamber)
    final offset = Vector2(
      (_rng.nextDouble() - 0.5) * 2,
      (_rng.nextDouble() - 0.5) * 2,
    );
    final spawnPos = queen.position + offset;
    ants.add(
      Ant(
        startPosition: spawnPos,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: AntCaste.larva,
        colonyId: queen.colonyId,
      ),
    );
    _updateAntCount();
  }

  void _matureLarva(Ant larva) {
    // Determine what caste the colony needs most
    final neededCaste = _determineNeededCaste(larva.colonyId);

    // Remove the larva and spawn the needed caste at its position
    ants.remove(larva);
    ants.add(
      Ant(
        startPosition: larva.position,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: neededCaste,
        colonyId: larva.colonyId,
      ),
    );
    // No need to update count - same number of ants
  }

  /// Determines what caste the colony needs most based on current composition.
  /// Target ratios: 65% workers, 20% soldiers, 15% nurses
  AntCaste _determineNeededCaste(int colonyId) {
    final colonyAnts = ants.where((a) => a.colonyId == colonyId && a.caste != AntCaste.larva && a.caste != AntCaste.queen).toList();
    if (colonyAnts.isEmpty) {
      return AntCaste.worker; // Default to worker for empty colony
    }

    final total = colonyAnts.length;
    final workers = colonyAnts.where((a) => a.caste == AntCaste.worker).length;
    final soldiers = colonyAnts.where((a) => a.caste == AntCaste.soldier).length;
    final nurses = colonyAnts.where((a) => a.caste == AntCaste.nurse).length;

    // Target ratios
    const targetWorkerRatio = 0.65;
    const targetSoldierRatio = 0.20;
    const targetNurseRatio = 0.15;

    // Calculate how much each caste is underrepresented
    final workerDeficit = targetWorkerRatio - (workers / total);
    final soldierDeficit = targetSoldierRatio - (soldiers / total);
    final nurseDeficit = targetNurseRatio - (nurses / total);

    // Pick the caste with the biggest deficit
    if (soldierDeficit > workerDeficit && soldierDeficit > nurseDeficit) {
      return AntCaste.soldier;
    } else if (nurseDeficit > workerDeficit) {
      return AntCaste.nurse;
    }
    return AntCaste.worker;
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

  void _scheduleNextFoodCheck() {
    _foodCheckTimer = 0;
    // Spawn new food every ~5 minutes (270-330 seconds)
    _nextFoodCheck = 270 + _rng.nextDouble() * 60;
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
    final deadAnts = <Ant>{};

    // Check for combat between ants from different colonies
    for (var i = 0; i < ants.length; i++) {
      final a = ants[i];
      if (a.isDead || deadAnts.contains(a)) continue;

      for (var j = i + 1; j < ants.length; j++) {
        final b = ants[j];
        if (b.isDead || deadAnts.contains(b)) continue;

        // Only fight if from different colonies
        if (a.colonyId == b.colonyId) continue;

        final distSq = a.position.distanceToSquared(b.position);
        if (distSq <= fightRadiusSq) {
          // Both ants deal damage based on aggression check
          final aWillFight = _rng.nextDouble() < a.aggression;
          final bWillFight = _rng.nextDouble() < b.aggression;

          if (aWillFight || bWillFight) {
            // Once combat starts, both fight
            final damageToA = _computeDamage(b, a);
            final damageToB = _computeDamage(a, b);
            a.applyDamage(damageToA);
            b.applyDamage(damageToB);

            if (a.isDead) deadAnts.add(a);
            if (b.isDead) deadAnts.add(b);
          }
        }
      }
    }

    if (deadAnts.isNotEmpty) {
      ants.removeWhere(deadAnts.contains);
      _updateAntCount();
    }
  }

  void _removeStuckAnts() {
    // Don't remove queens or larvae - they don't move much by design
    final stuckAnts = ants.where((a) =>
      a.isStuck &&
      a.caste != AntCaste.queen &&
      a.caste != AntCaste.larva
    ).toList();
    if (stuckAnts.isNotEmpty) {
      ants.removeWhere(stuckAnts.contains);
      _updateAntCount();
    }
  }

  double _computeDamage(Ant attacker, Ant defender) {
    final variance = 0.8 + _rng.nextDouble() * 0.5;
    final mitigation = defender.defense * (0.3 + _rng.nextDouble() * 0.2);
    return math.max(0.2, attacker.attack * variance - mitigation);
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
      'zones': _encodeUint8(Uint8List.fromList(world.zones)),
      'dirtHealth': _encodeFloat32(world.dirtHealth),
      'foodAmount': _encodeUint8(Uint8List.fromList(world.foodAmount)),
      // Per-colony pheromone layers
      'foodPheromones0': _encodeFloat32(world.foodPheromones0),
      'foodPheromones1': _encodeFloat32(world.foodPheromones1),
      'homePheromones0': _encodeFloat32(world.homePheromones0),
      'homePheromones1': _encodeFloat32(world.homePheromones1),
      'blockedPheromones': _encodeFloat32(world.blockedPheromones),
      'nest': {'x': world.nestPosition.x, 'y': world.nestPosition.y},
      'nest1': {'x': world.nest1Position.x, 'y': world.nest1Position.y},
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

