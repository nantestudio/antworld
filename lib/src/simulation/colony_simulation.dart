import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../services/analytics_service.dart';
import 'ant.dart';
import 'simulation_config.dart';
import 'world_generator.dart';
import 'world_grid.dart';

class ColonySimulation {
  ColonySimulation(this.config)
    : antCount = ValueNotifier<int>(0),
      foodCollected = ValueNotifier<int>(0),
      colony0Food = ValueNotifier<int>(0),
      colony1Food = ValueNotifier<int>(0),
      pheromonesVisible = ValueNotifier<bool>(true),
      foodScentVisible = ValueNotifier<bool>(true),
      foodPheromonesVisible = ValueNotifier<bool>(true),
      homePheromonesVisible = ValueNotifier<bool>(true),
      antSpeedMultiplier = ValueNotifier<double>(0.2),
      daysPassed = ValueNotifier<int>(1),
      elapsedTime = ValueNotifier<double>(0.0),
      paused = ValueNotifier<bool>(false) {
    world = WorldGrid(config);
  }

  SimulationConfig config;
  late WorldGrid world;
  final List<Ant> ants = []; // Contains ants from all colonies
  final ValueNotifier<int> antCount;
  final ValueNotifier<int> foodCollected;
  final ValueNotifier<int> colony0Food;
  final ValueNotifier<int> colony1Food;
  final ValueNotifier<bool> pheromonesVisible;
  final ValueNotifier<bool> foodScentVisible;
  final ValueNotifier<bool> foodPheromonesVisible;
  final ValueNotifier<bool> homePheromonesVisible;
  final ValueNotifier<double> antSpeedMultiplier;
  final ValueNotifier<int> daysPassed;
  final ValueNotifier<double> elapsedTime;
  final ValueNotifier<bool> paused;

  final math.Random _rng = math.Random();
  int _storedFood = 0;
  // Per-colony food tracking for reproduction
  final List<int> _colonyFood = [0, 0, 0, 0]; // Supports up to 4 colonies
  final List<int> _colonyQueuedAnts = [0, 0, 0, 0]; // Supports up to 4 colonies
  // Princess spawning: accumulate food, spawn princess egg when threshold reached
  static const int _foodForPrincess =
      75; // Food needed to spawn a princess egg (higher threshold)
  static const int _maxPrincessesPerColony = 2;
  final List<int> _princessFoodAccumulator = [
    0,
    0,
    0,
    0,
  ]; // Per-colony accumulator
  final List<int> _colonyQueuedPrincesses = [
    0,
    0,
    0,
    0,
  ]; // Pending princess larvae per colony
  int _physicsFrame = 0;
  int? _lastSeed;
  double _elapsedTime = 0.0;
  double _foodCheckTimer = 0.0;
  double _nextFoodCheck = 300.0; // ~5 minutes between food spawns
  final List<_BuildTask> _buildQueue = [];
  double _roomCheckTimer = 0.0;
  static const double _roomCheckInterval = 30.0;
  double _resourceCheckTimer = 0.0;
  static const double _resourceCheckInterval = 15.0;
  int _nextBuildTaskId = 1;

  // Reusable structures for separation (avoid per-frame allocation)
  final Map<int, List<Ant>> _spatialHash = {};
  final Map<Ant, Vector2> _separationAdjustments = {};
  final List<List<Ant>> _spatialHashListPool = [];

  // Cached stats (updated in _updateAntCount for O(1) access)
  int _enemyCount = 0;
  int _restingCount = 0;
  int _carryingFoodCount = 0;
  int _foragingCount = 0;
  int _workerCount = 0;
  int _soldierCount = 0;
  int _nurseCount = 0;
  int _larvaCount = 0;
  int _eggCount = 0;
  int _queenCount = 0;
  int _princessCount = 0;
  int _enemy1WorkerCount = 0;
  int _enemy1SoldierCount = 0;
  int _enemy1NurseCount = 0;
  int _enemy1LarvaCount = 0;
  int _enemy1EggCount = 0;
  int _enemy1QueenCount = 0;
  int _enemy1PrincessCount = 0;

  bool get showPheromones => pheromonesVisible.value;
  bool get showFoodPheromones => foodPheromonesVisible.value;
  bool get showHomePheromones => homePheromonesVisible.value;
  bool get showFoodScent => foodScentVisible.value;
  int? get lastSeed => _lastSeed;

  // Stats getters for UI - use cached values (O(1) instead of O(n))
  int get enemyCount => _enemyCount;
  int get restingCount => _restingCount;
  int get carryingFoodCount => _carryingFoodCount;
  int get foragingCount => _foragingCount;
  int get workerCount => _workerCount;
  int get soldierCount => _soldierCount;
  int get nurseCount => _nurseCount;
  int get larvaCount => _larvaCount;
  int get eggCount => _eggCount;
  int get queenCount => _queenCount;
  int get princessCount => _princessCount;

  // Colony 1 stats
  int get enemy1WorkerCount => _enemy1WorkerCount;
  int get enemy1SoldierCount => _enemy1SoldierCount;
  int get enemy1NurseCount => _enemy1NurseCount;
  int get enemy1LarvaCount => _enemy1LarvaCount;
  int get enemy1EggCount => _enemy1EggCount;
  int get enemy1QueenCount => _enemy1QueenCount;
  int get enemy1PrincessCount => _enemy1PrincessCount;

  void initialize() {
    world.reset();
    world.carveNest();
    ants.clear();
    Ant.resetIdCounter();
    _storedFood = 0;
    for (var i = 0; i < 4; i++) {
      _colonyFood[i] = 0;
      _colonyQueuedAnts[i] = 0;
      _princessFoodAccumulator[i] = 0;
      _colonyQueuedPrincesses[i] = 0;
    }
    _elapsedTime = 0.0;
    elapsedTime.value = 0.0;
    _scheduleNextFoodCheck();
    foodCollected.value = 0;
    colony0Food.value = 0;
    colony1Food.value = 0;
    daysPassed.value = 1;

    _spawnInitialColony();
    _updateAntCount();
  }

  void _spawnInitialColony() {
    // Spawn ants for all colonies based on config
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      // Always spawn one queen and one princess heir
      _spawnAnt(caste: AntCaste.queen, colonyId: colonyId);
      _spawnAnt(caste: AntCaste.princess, colonyId: colonyId);

      // Calculate base counts: 80% workers, 10% nurses, 10% soldiers
      final baseNurse = config.startingAnts * 0.10; // ~10% nurses
      final baseSoldier = config.startingAnts * 0.10; // ~10% soldiers

      // Add randomness: base * (0.8 to 1.2)
      final nurseCount = math.max(
        2,
        (baseNurse * (0.8 + _rng.nextDouble() * 0.4)).round(),
      );
      final soldierCount = math.max(
        2,
        (baseSoldier * (0.8 + _rng.nextDouble() * 0.4)).round(),
      );

      // Spawn nurses
      for (var i = 0; i < nurseCount; i++) {
        _spawnAnt(caste: AntCaste.nurse, colonyId: colonyId);
      }

      // Spawn soldiers
      for (var i = 0; i < soldierCount; i++) {
        _spawnAnt(caste: AntCaste.soldier, colonyId: colonyId);
      }

      // Allocate remaining population between builders, workers, and seed larvae
      var remaining = config.startingAnts - 2 - nurseCount - soldierCount;
      final builderCount = math.max(3, (remaining * 0.2).round());
      remaining = math.max(0, remaining - builderCount);

      for (var i = 0; i < builderCount; i++) {
        _spawnAnt(caste: AntCaste.builder, colonyId: colonyId);
      }

      final larvaSeed = math.max(2, (remaining * 0.1).round());
      remaining = math.max(0, remaining - larvaSeed);

      final workerCount = math.max(0, remaining);
      for (var i = 0; i < workerCount; i++) {
        _spawnAnt(caste: AntCaste.worker, colonyId: colonyId);
      }

      for (var i = 0; i < larvaSeed; i++) {
        _spawnAnt(caste: AntCaste.larva, colonyId: colonyId);
      }
    }
  }

  void update(double dt) {
    if (paused.value) return; // Skip simulation when paused

    final double clampedDt = dt.clamp(0.0, 0.05);
    final decayFactor = math.pow(config.decayPerSecond, clampedDt).toDouble();
    final double antSpeed = config.antSpeed * antSpeedMultiplier.value;
    world.decay(decayFactor, config.decayThreshold);

    // Diffuse food scent through air cells (spreads like gas through tunnels)
    // Run multiple iterations for faster spreading at low simulation speeds
    final diffuseIterations = antSpeedMultiplier.value < 1.0 ? 3 : 2;
    for (var i = 0; i < diffuseIterations; i++) {
      world.diffuseFoodScent();
    }

    _roomCheckTimer += clampedDt;
    if (_roomCheckTimer >= _roomCheckInterval) {
      _checkRoomCapacity();
      _roomCheckTimer = 0.0;
    }

    _resourceCheckTimer += clampedDt;
    if (_resourceCheckTimer >= _resourceCheckInterval) {
      _checkColonyResources();
      _resourceCheckTimer = 0.0;
    }

    // Track elapsed time and update days (1 minute = 1 day, affected by speed multiplier)
    _elapsedTime += clampedDt * antSpeedMultiplier.value;
    elapsedTime.value = _elapsedTime;
    final newDays = (_elapsedTime / 60.0).floor() + 1;
    if (newDays != daysPassed.value) {
      final oldDays = daysPassed.value;
      daysPassed.value = newDays;

      // Track day milestones (10, 25, 50, 100, etc)
      const milestones = [10, 25, 50, 100, 200, 500];
      for (final milestone in milestones) {
        if (oldDays < milestone && newDays >= milestone) {
          AnalyticsService.instance.logDayMilestone(
            day: milestone,
            totalAnts: ants.length,
            totalFood: _storedFood,
          );
          break;
        }
      }
    }

    final eggsToHatch = <Ant>[];
    final larvaeToMature = <Ant>[];
    final queensLayingEggs = <Ant>[];
    final nursesSignaling = <Ant>[];
    // Use toList() to avoid ConcurrentModificationError if ants list changes
    for (final ant in ants.toList()) {
      final result = ant.update(
        clampedDt,
        config,
        world,
        _rng,
        antSpeed,
        attackTarget: null,
      );

      if (ant.caste == AntCaste.queen && result) {
        // Queen wants to lay an egg - defer spawning until after iteration
        queensLayingEggs.add(ant);
      } else if (ant.caste == AntCaste.nurse && result) {
        // Nurse signals wanting to pick up or drop an egg
        nursesSignaling.add(ant);
      } else if (ant.caste == AntCaste.egg && ant.isReadyToHatch) {
        final nurseryRoom = world.getNurseryRoom(ant.colonyId);
        if (nurseryRoom != null) {
          if (!nurseryRoom.contains(ant.position) &&
              !nurseryRoom.isOverCapacity) {
            final jitter = Vector2(
              (_rng.nextDouble() - 0.5) * 1.5,
              (_rng.nextDouble() - 0.5) * 1.5,
            );
            final target = nurseryRoom.center + jitter;
            if (world.isWalkable(target.x, target.y)) {
              ant.position.setFrom(target);
            } else {
              ant.position.setFrom(nurseryRoom.center);
            }
          }
        }
        eggsToHatch.add(ant);
      } else if (ant.caste == AntCaste.larva && ant.isReadyToMature) {
        // Larva ready to become an adult
        larvaeToMature.add(ant);
      } else if (result && ant.caste == AntCaste.builder) {
        final completedId = ant.takeCompletedBuilderTaskId();
        if (completedId != null) {
          _completeBuildTask(completedId);
        }
      } else if (result && ant.caste == AntCaste.worker) {
        // Worker delivered food - track per colony for reproduction
        _storedFood += 1;
        foodCollected.value = _storedFood;
        _colonyFood[ant.colonyId] += 1;
        // Update per-colony food ValueNotifiers for UI
        if (ant.colonyId == 0) {
          colony0Food.value = _colonyFood[0];
        } else {
          colony1Food.value = _colonyFood[1];
        }
        // Food enables egg production - queue eggs instead of adults
        if (_colonyFood[ant.colonyId] % config.foodPerNewAnt == 0) {
          _colonyQueuedAnts[ant.colonyId] += 1;
        }
        // Princess spawning: accumulate food for princess production
        _princessFoodAccumulator[ant.colonyId] += 1;
        if (_princessFoodAccumulator[ant.colonyId] >= _foodForPrincess) {
          // Check if colony can have more princesses
          final currentPrincessCount = _getPrincessCountForColony(ant.colonyId);
          if (currentPrincessCount < _maxPrincessesPerColony) {
            _spawnPrincessEgg(ant.colonyId);
          }
          _princessFoodAccumulator[ant.colonyId] = 0;
        }
      }
    }

    // Spawn eggs from queens (after iteration to avoid concurrent modification)
    for (final queen in queensLayingEggs) {
      _spawnEggAtQueen(queen);
    }

    // Hatch eggs into larvae
    for (final egg in eggsToHatch) {
      _hatchEgg(egg);
    }

    // Mature larvae into adults
    for (final larva in larvaeToMature) {
      _matureLarva(larva);
    }

    // Handle nurse egg pickup/drop
    _processNurseEggTransfer(nursesSignaling);

    // Update egg positions to follow carrying nurses
    _updateCarriedEggs();

    // Nurses feed resting/injured ants with stored food
    if (_physicsFrame % 10 == 0) {
      _processNurseFeeding();
    }

    // Run physics/collision less frequently for performance
    // Separation and combat don't need to run every single frame
    _physicsFrame++;
    if (_physicsFrame % 2 == 0) {
      _applySeparation();
    }
    if (_physicsFrame % 3 == 0) {
      _resolveCombat();
    }
    if (_physicsFrame % 20 == 0) {
      _processBuildQueue();
    }
    if (_physicsFrame % 30 == 0) {
      // Queens emit strong pheromones towards food to guide ants (less frequent)
      _queenFoodGuidance();
      _checkThreatsAndTriggerDefense();
    }
    if (_physicsFrame % 60 == 0) {
      _removeStuckAnts();
      _removeOldAnts();
    }
    _flushSpawnQueue();

    _foodCheckTimer += clampedDt;
    if (_foodCheckTimer >= _nextFoodCheck) {
      _maintainFoodSupply();
      _scheduleNextFoodCheck();
    }
  }

  void togglePheromones() {
    final enable = !showPheromones;
    pheromonesVisible.value = enable;
    foodPheromonesVisible.value = enable;
    homePheromonesVisible.value = enable;
  }

  void toggleFoodScent() {
    foodScentVisible.value = !foodScentVisible.value;
  }

  void togglePause() {
    paused.value = !paused.value;
  }

  void setPheromoneVisibility(bool visible) {
    pheromonesVisible.value = visible;
    foodPheromonesVisible.value = visible;
    homePheromonesVisible.value = visible;
  }

  void setFoodScentVisibility(bool visible) {
    foodScentVisible.value = visible;
  }

  void setFoodPheromoneVisibility(bool visible) {
    foodPheromonesVisible.value = visible;
    pheromonesVisible.value = visible || homePheromonesVisible.value;
  }

  void setHomePheromoneVisibility(bool visible) {
    homePheromonesVisible.value = visible;
    pheromonesVisible.value = visible || foodPheromonesVisible.value;
  }

  void setRestingEnabled(bool enabled) {
    if (config.restEnabled == enabled) {
      return;
    }
    config = config.copyWith(restEnabled: enabled);
    if (!enabled) {
      for (final ant in ants.toList()) {
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
    final clamped = value.clamp(5.0, 200.0).toDouble();
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
    for (var i = 0; i < 4; i++) {
      _colonyFood[i] = 0;
      _colonyQueuedAnts[i] = 0;
    }
    _elapsedTime = 0.0;
    _scheduleNextFoodCheck();
    foodCollected.value = 0;
    colony0Food.value = 0;
    colony1Food.value = 0;
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

  void generateRandomWorld({
    int? seed,
    int? cols,
    int? rows,
    int? colonyCount,
  }) {
    // Clean up first to free resources
    prepareForNewWorld();

    final generator = WorldGenerator();
    final actualSeed = seed ?? _rng.nextInt(0x7fffffff);
    final generated = generator.generate(
      baseConfig: config,
      seed: actualSeed,
      cols: cols,
      rows: rows,
      colonyCount: colonyCount,
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
    world = WorldGrid(
      config,
      nestOverride: nestOverride,
      nest1Override: nest1Override,
    );
    if (worldData != null) {
      final zonesStr = worldData['zones'] as String?;
      final dirtTypesStr = worldData['dirtTypes'] as String?;
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
        dirtTypesData: dirtTypesStr != null ? _decodeUint8(dirtTypesStr) : null,
        // Legacy pheromone data (will be copied to colony 0 layer)
        foodPheromoneData: legacyFoodStr != null
            ? _decodeFloat32(legacyFoodStr)
            : null,
        homePheromoneData: legacyHomeStr != null
            ? _decodeFloat32(legacyHomeStr)
            : null,
        // Per-colony pheromone data
        foodPheromone0Data: food0Str != null ? _decodeFloat32(food0Str) : null,
        foodPheromone1Data: food1Str != null ? _decodeFloat32(food1Str) : null,
        homePheromone0Data: home0Str != null ? _decodeFloat32(home0Str) : null,
        homePheromone1Data: home1Str != null ? _decodeFloat32(home1Str) : null,
        zonesData: zonesStr != null ? _decodeUint8(zonesStr) : null,
        blockedPheromoneData: blockedStr != null
            ? _decodeFloat32(blockedStr)
            : null,
        foodAmountData: foodAmountStr != null
            ? _decodeUint8(foodAmountStr)
            : null,
      );

      // Load rooms
      final roomsData = worldData['rooms'] as List<dynamic>?;
      if (roomsData != null) {
        for (final roomJson in roomsData) {
          world.rooms.add(Room.fromJson(Map<String, dynamic>.from(roomJson)));
        }
      }
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
    for (var i = 0; i < 4; i++) {
      _colonyFood[i] = 0;
      _colonyQueuedAnts[i] = 0;
    }
    colony0Food.value = 0;
    colony1Food.value = 0;
    antSpeedMultiplier.value =
        (snapshot['antSpeedMultiplier'] as num?)?.toDouble() ?? 0.2;
    pheromonesVisible.value = snapshot['pheromonesVisible'] as bool? ?? true;
    _lastSeed = (snapshot['seed'] as num?)?.toInt();
    _elapsedTime = (snapshot['elapsedTime'] as num?)?.toDouble() ?? 0.0;
    daysPassed.value = (snapshot['daysPassed'] as num?)?.toInt() ?? 0;

    // Ensure both colonies have a queen (for migrating old saves)
    _ensureQueensExist();
  }

  /// Ensures all colonies have at least one queen
  void _ensureQueensExist() {
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      final hasQueen = ants.any(
        (a) => a.colonyId == colonyId && a.caste == AntCaste.queen,
      );
      if (!hasQueen) {
        _spawnAnt(caste: AntCaste.queen, colonyId: colonyId);
      }
    }
  }

  void addAnts(int count) {
    if (count <= 0) return;
    // Add ants to all colonies equally
    for (var i = 0; i < count; i++) {
      for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
        _spawnAnt(colonyId: colonyId);
      }
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

  void _spawnEggAtQueen(Ant queen) {
    // Spawn egg near the queen's position (in queen chamber)
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
        caste: AntCaste.egg,
        colonyId: queen.colonyId,
      ),
    );
    _updateAntCount();
  }

  /// Get the count of princesses for a specific colony
  int _getPrincessCountForColony(int colonyId) {
    return ants
        .where(
          (ant) => ant.colonyId == colonyId && ant.caste == AntCaste.princess,
        )
        .length;
  }

  /// Spawn a princess egg at the queen's position
  void _spawnPrincessEgg(int colonyId) {
    // Find the queen for this colony
    final queen = ants
        .where((ant) => ant.colonyId == colonyId && ant.caste == AntCaste.queen)
        .firstOrNull;
    if (queen == null) return;

    // Spawn princess egg near the queen
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
        caste: AntCaste.egg,
        colonyId: colonyId,
      ),
    );
    // Mark this egg as destined to become a princess (stored in larva stage)
    // Note: We'll handle princess maturation in _matureLarva by tracking which eggs should become princesses
    _colonyQueuedPrincesses[colonyId] += 1;
    _updateAntCount();
  }

  void _hatchEgg(Ant egg) {
    // Transform egg into larva at the same position
    ants.remove(egg);
    ants.add(
      Ant(
        startPosition: egg.position,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: AntCaste.larva,
        colonyId: egg.colonyId,
      ),
    );
    // No need to update count - same number of ants
  }

  void _matureLarva(Ant larva) {
    AntCaste neededCaste;

    // Check if this larva should become a princess (queued from food collection)
    final hasPrincess = _getPrincessCountForColony(larva.colonyId) > 0;
    if (!hasPrincess && _colonyQueuedPrincesses[larva.colonyId] == 0) {
      neededCaste = AntCaste.princess;
    } else if (_colonyQueuedPrincesses[larva.colonyId] > 0) {
      neededCaste = AntCaste.princess;
      _colonyQueuedPrincesses[larva.colonyId] -= 1;
    } else {
      // Determine what caste the colony needs most
      neededCaste = _determineNeededCaste(larva.colonyId);
    }

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

  /// Process nurses that are signaling egg pickup or drop
  void _processNurseEggTransfer(List<Ant> nurses) {
    for (final nurse in nurses) {
      final homeRoom = world.getHomeRoom(nurse.colonyId);
      final nurseryRoom = world.getNurseryRoom(nurse.colonyId);

      if (nurse.isCarryingEgg) {
        // Nurse is carrying and in nursery - drop the egg
        if (nurseryRoom != null && nurseryRoom.contains(nurse.position)) {
          nurse.dropEgg();
        }
      } else {
        // Nurse wants to pick up - find an egg in home room
        if (homeRoom != null && homeRoom.contains(nurse.position)) {
          final eggInHome = ants.cast<Ant?>().firstWhere(
            (a) =>
                a!.caste == AntCaste.egg &&
                a.colonyId == nurse.colonyId &&
                homeRoom.contains(a.position) &&
                !_isEggBeingCarried(a.id),
            orElse: () => null,
          );
          if (eggInHome != null) {
            nurse.pickUpEgg(eggInHome.id);
          }
        }
      }
    }
  }

  /// Check if an egg is already being carried by a nurse
  bool _isEggBeingCarried(int eggId) {
    return ants.any(
      (a) => a.caste == AntCaste.nurse && a.carryingEggId == eggId,
    );
  }

  /// Update positions of eggs being carried by nurses
  void _updateCarriedEggs() {
    for (final nurse in ants) {
      if (nurse.caste != AntCaste.nurse || !nurse.isCarryingEgg) continue;

      // Find the egg this nurse is carrying
      final egg = ants.cast<Ant?>().firstWhere(
        (a) => a!.id == nurse.carryingEggId,
        orElse: () => null,
      );
      if (egg != null) {
        // Move egg to nurse's position
        egg.position.setFrom(nurse.position);
      } else {
        // Egg no longer exists (hatched or died), drop reference
        nurse.dropEgg();
      }
    }
  }

  /// Nurses feed resting or injured ants using stored colony food
  void _processNurseFeeding() {
    const feedRadius = 2.0; // Nurse must be within 2 cells to feed
    const feedRadiusSq = feedRadius * feedRadius;

    for (final nurse in ants) {
      if (nurse.caste != AntCaste.nurse || nurse.isDead) {
        continue;
      }
      if (nurse.isCarryingEgg) {
        continue; // Can't feed while carrying egg
      }

      // Check if colony has food to share
      if (_colonyFood[nurse.colonyId] <= 0) {
        continue;
      }

      // Find nearby ants that need feeding (resting or low HP)
      for (final target in ants) {
        if (target.colonyId != nurse.colonyId) {
          continue;
        }
        if (target.isDead || target == nurse) {
          continue;
        }
        if (target.caste == AntCaste.egg || target.caste == AntCaste.larva) {
          continue;
        }

        final distSq = nurse.position.distanceToSquared(target.position);
        if (distSq > feedRadiusSq) {
          continue;
        }

        // Check if ant needs feeding: resting OR low HP
        final needsEnergy = target.state == AntState.rest;
        final needsHealing = target.hp < target.maxHp * 0.8;

        if (needsEnergy || needsHealing) {
          // Spend 1 food to feed this ant
          _colonyFood[nurse.colonyId] -= 1;
          if (nurse.colonyId == 0) {
            colony0Food.value = _colonyFood[0];
          } else {
            colony1Food.value = _colonyFood[1];
          }

          // Restore ant's energy to full and wake them up
          if (needsEnergy) {
            target.energy = config.energyCapacity;
            target.exitRestState();
          }

          // Heal some HP
          if (needsHealing) {
            target.hp = (target.hp + target.maxHp * 0.3).clamp(0, target.maxHp);
          }

          // One feeding per nurse per cycle
          break;
        }
      }
    }
  }

  /// Determines what caste the colony needs most based on current composition.
  /// Target ratios: 55% workers, 15% soldiers, 15% nurses, 15% builders
  AntCaste _determineNeededCaste(int colonyId) {
    final colonyAnts = ants
        .where(
          (a) =>
              a.colonyId == colonyId &&
              a.caste != AntCaste.larva &&
              a.caste != AntCaste.egg &&
              a.caste != AntCaste.queen &&
              a.caste != AntCaste.princess,
        )
        .toList();
    if (colonyAnts.isEmpty) {
      return AntCaste.worker; // Default to worker for empty colony
    }

    final total = colonyAnts.length;
    final workers = colonyAnts.where((a) => a.caste == AntCaste.worker).length;
    final soldiers = colonyAnts
        .where((a) => a.caste == AntCaste.soldier)
        .length;
    final nurses = colonyAnts.where((a) => a.caste == AntCaste.nurse).length;
    final builders = colonyAnts
        .where((a) => a.caste == AntCaste.builder)
        .length;

    // Target ratios (55% workers, 15% each for specialists)
    const targetWorkerRatio = 0.55;
    const targetSoldierRatio = 0.15;
    const targetNurseRatio = 0.15;
    const targetBuilderRatio = 0.15;

    // Calculate how much each caste is underrepresented
    final workerDeficit = targetWorkerRatio - (workers / total);
    final soldierDeficit = targetSoldierRatio - (soldiers / total);
    final nurseDeficit = targetNurseRatio - (nurses / total);
    final builderDeficit = targetBuilderRatio - (builders / total);

    // Pick the caste with the biggest deficit
    if (builderDeficit > workerDeficit &&
        builderDeficit > soldierDeficit &&
        builderDeficit > nurseDeficit) {
      return AntCaste.builder;
    } else if (soldierDeficit > workerDeficit &&
        soldierDeficit > nurseDeficit) {
      return AntCaste.soldier;
    } else if (nurseDeficit > workerDeficit) {
      return AntCaste.nurse;
    }
    return AntCaste.worker;
  }

  void _flushSpawnQueue() {
    // Spawn queued eggs for each colony based on their food deliveries
    // Food enables reproduction through the proper lifecycle: egg -> larva -> adult
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      final queued = _colonyQueuedAnts[colonyId];
      if (queued > 0) {
        // Find the queen to spawn eggs near her
        final queen = ants
            .where((a) => a.colonyId == colonyId && a.caste == AntCaste.queen)
            .firstOrNull;
        for (var i = 0; i < queued; i++) {
          if (queen != null) {
            // Spawn egg at queen's position
            _spawnEggAtQueen(queen);
          } else {
            // No queen - spawn egg at nest center (colony can survive but slower)
            _spawnEggAtNest(colonyId);
          }
        }
        _colonyQueuedAnts[colonyId] = 0;
      }
    }
  }

  void _spawnEggAtNest(int colonyId) {
    // Spawn egg at nest center (fallback when no queen)
    final nestPos = world.getNestPosition(colonyId);
    final offset = Vector2(
      (_rng.nextDouble() - 0.5) * 3,
      (_rng.nextDouble() - 0.5) * 3,
    );
    ants.add(
      Ant(
        startPosition: nestPos + offset,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: AntCaste.egg,
        colonyId: colonyId,
      ),
    );
    _updateAntCount();
  }

  void _updateAntCount() {
    // Reset all counters
    _enemyCount = 0;
    _restingCount = 0;
    _carryingFoodCount = 0;
    _foragingCount = 0;
    _workerCount = 0;
    _soldierCount = 0;
    _nurseCount = 0;
    _larvaCount = 0;
    _eggCount = 0;
    _queenCount = 0;
    _princessCount = 0;
    _enemy1WorkerCount = 0;
    _enemy1SoldierCount = 0;
    _enemy1NurseCount = 0;
    _enemy1LarvaCount = 0;
    _enemy1EggCount = 0;
    _enemy1QueenCount = 0;
    _enemy1PrincessCount = 0;

    // Single pass through all ants
    for (final ant in ants.toList()) {
      if (ant.colonyId == 0) {
        // Colony 0 stats
        if (ant.state == AntState.rest) _restingCount++;
        if (ant.hasFood) _carryingFoodCount++;
        if (ant.state == AntState.forage && !ant.hasFood) _foragingCount++;
        switch (ant.caste) {
          case AntCaste.worker:
            _workerCount++;
          case AntCaste.soldier:
            _soldierCount++;
          case AntCaste.nurse:
            _nurseCount++;
          case AntCaste.larva:
            _larvaCount++;
          case AntCaste.egg:
            _eggCount++;
          case AntCaste.queen:
            _queenCount++;
          case AntCaste.princess:
            _princessCount++;
          case AntCaste.drone:
          case AntCaste.builder:
            break;
        }
      } else {
        // Enemy colony stats
        _enemyCount++;
        if (ant.colonyId == 1) {
          switch (ant.caste) {
            case AntCaste.worker:
              _enemy1WorkerCount++;
            case AntCaste.soldier:
              _enemy1SoldierCount++;
            case AntCaste.nurse:
              _enemy1NurseCount++;
            case AntCaste.larva:
              _enemy1LarvaCount++;
            case AntCaste.egg:
              _enemy1EggCount++;
            case AntCaste.queen:
              _enemy1QueenCount++;
            case AntCaste.princess:
              _enemy1PrincessCount++;
            case AntCaste.drone:
            case AntCaste.builder:
              break;
          }
        }
      }
    }

    antCount.value = ants.length;
  }

  void _scheduleNextFoodCheck() {
    _foodCheckTimer = 0;
    // Spawn new food every ~5 minutes (270-330 seconds)
    _nextFoodCheck = 270 + _rng.nextDouble() * 60;
  }

  void _maintainFoodSupply() {
    // Only spawn food when the map is completely empty of food
    if (world.foodCount > 0) {
      return;
    }
    // Spawn a single food cluster in an open area (not on rocks)
    final spot = _randomOpenCell();
    if (spot == null) {
      return;
    }
    final radius = 2 + _rng.nextInt(3);
    world.placeFood(spot, radius);
  }

  void _checkRoomCapacity() {
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      final colonyRooms = world.rooms.where(
        (room) => room.colonyId == colonyId,
      );
      for (final room in colonyRooms) {
        final occupancy = _measureRoomOccupancy(room);
        room.currentOccupancy = occupancy;
        room.needsExpansion = room.isOverCapacity;
        if (room.needsExpansion) {
          _queueNewRoom(colonyId, room.type);
        }
      }
    }
  }

  int _measureRoomOccupancy(Room room) {
    switch (room.type) {
      case RoomType.home:
        return ants
            .where(
              (ant) =>
                  ant.colonyId == room.colonyId &&
                  room.contains(ant.position) &&
                  (ant.caste == AntCaste.queen ||
                      ant.caste == AntCaste.princess ||
                      ant.caste == AntCaste.nurse),
            )
            .length;
      case RoomType.nursery:
        return ants
            .where(
              (ant) =>
                  ant.colonyId == room.colonyId &&
                  room.contains(ant.position) &&
                  (ant.caste == AntCaste.egg || ant.caste == AntCaste.larva),
            )
            .length;
      case RoomType.foodStorage:
        return _countFoodInRoom(room);
      case RoomType.barracks:
        return ants
            .where(
              (ant) =>
                  ant.colonyId == room.colonyId &&
                  room.contains(ant.position) &&
                  (ant.caste == AntCaste.worker ||
                      ant.caste == AntCaste.soldier ||
                      ant.caste == AntCaste.builder) &&
                  ant.state == AntState.rest,
            )
            .length;
    }
  }

  int _countFoodInRoom(Room room) {
    final cx = room.center.x.floor();
    final cy = room.center.y.floor();
    final radius = room.radius.ceil();
    var total = 0;
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!world.isInsideIndex(x, y)) continue;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > room.radius) continue;
        final idx = world.index(x, y);
        if (world.cells[idx] == CellType.food.index) {
          total += world.foodAmount[idx];
        }
      }
    }
    return total;
  }

  void _queueNewRoom(int colonyId, RoomType type) {
    final hasTask = _buildQueue.any(
      (task) =>
          task.colonyId == colonyId &&
          task.kind == _BuildTaskKind.room &&
          task.roomType == type,
    );
    if (hasTask) return;

    final radius = _roomRadiusFor(type);
    final location = world.findNewRoomLocation(colonyId, type, radius);
    if (location == null) {
      return;
    }

    _buildQueue.add(
      _BuildTask(
        id: _nextBuildTaskId++,
        kind: _BuildTaskKind.room,
        colonyId: colonyId,
        targetLocation: location.clone(),
        radius: radius,
        roomType: type,
      ),
    );
  }

  double _roomRadiusFor(RoomType type) {
    switch (type) {
      case RoomType.home:
        return 4.0;
      case RoomType.nursery:
        return 3.0;
      case RoomType.foodStorage:
        return 3.5;
      case RoomType.barracks:
        return 3.5;
    }
  }

  void _processBuildQueue() {
    if (_buildQueue.isEmpty) return;
    _reclaimBuilderTasks();
    for (final task in _buildQueue) {
      if (task.inProgress) {
        continue;
      }
      final builder = _findAvailableBuilder(task.colonyId);
      if (builder == null) {
        continue;
      }

      task.inProgress = true;
      task.assignedBuilderId = builder.id;
      final builderTask = switch (task.kind) {
        _BuildTaskKind.room => BuilderTask.buildingRoom,
        _BuildTaskKind.reinforce => BuilderTask.reinforcingWall,
        _BuildTaskKind.defense => BuilderTask.emergencyDefense,
      };
      builder.assignBuilderTask(
        task: builderTask,
        target: task.targetLocation,
        roomType: task.roomType,
        radius: task.radius,
        emergency: task.emergency,
        taskId: task.id,
      );
    }
  }

  void _reclaimBuilderTasks() {
    for (final task in _buildQueue) {
      if (!task.inProgress) continue;
      final builder = _findAntById(task.assignedBuilderId);
      final shouldReset =
          builder == null ||
          builder.isDead ||
          builder.caste != AntCaste.builder ||
          builder.colonyId != task.colonyId;
      if (shouldReset) {
        task.inProgress = false;
        task.assignedBuilderId = -1;
      }
    }
  }

  Ant? _findAvailableBuilder(int colonyId) {
    for (final ant in ants) {
      if (ant.colonyId == colonyId &&
          ant.caste == AntCaste.builder &&
          !ant.isDead &&
          ant.isBuilderIdle) {
        return ant;
      }
    }
    return null;
  }

  Ant? _findAntById(int id) {
    for (final ant in ants) {
      if (ant.id == id) {
        return ant;
      }
    }
    return null;
  }

  void _completeBuildTask(int taskId) {
    final index = _buildQueue.indexWhere((task) => task.id == taskId);
    if (index == -1) {
      return;
    }
    final task = _buildQueue.removeAt(index);
    if (task.kind == _BuildTaskKind.room && task.roomType != null) {
      world.addRoom(
        Room(
          type: task.roomType!,
          center: task.targetLocation.clone(),
          radius: task.radius,
          colonyId: task.colonyId,
        ),
      );
    }
  }

  void _checkThreatsAndTriggerDefense() {
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      final nestPos = world.getNestPosition(colonyId);
      final threats = ants
          .where(
            (ant) =>
                ant.colonyId != colonyId &&
                !ant.isDead &&
                ant.position.distanceTo(nestPos) < config.nestRadius * 3,
          )
          .toList();
      if (threats.isEmpty) {
        continue;
      }
      _triggerDefenseBuilding(colonyId, threats, nestPos);
    }
  }

  void _triggerDefenseBuilding(
    int colonyId,
    List<Ant> threats,
    Vector2 nestPos,
  ) {
    threats.sort(
      (a, b) => a.position
          .distanceTo(nestPos)
          .compareTo(b.position.distanceTo(nestPos)),
    );
    final closest = threats.first;
    final direction = (closest.position - nestPos);
    if (direction.length2 == 0) {
      return;
    }
    direction.normalize();
    final target = Vector2(
      nestPos.x + direction.x * config.nestRadius * 1.5,
      nestPos.y + direction.y * config.nestRadius * 1.5,
    );
    final existing = _buildQueue.any(
      (task) =>
          task.kind == _BuildTaskKind.defense &&
          task.colonyId == colonyId &&
          task.targetLocation.distanceTo(target) < 2.0,
    );
    if (existing) {
      return;
    }

    _buildQueue.add(
      _BuildTask(
        id: _nextBuildTaskId++,
        kind: _BuildTaskKind.defense,
        colonyId: colonyId,
        targetLocation: target,
        radius: 2.0,
        emergency: true,
      ),
    );
  }

  void _applySeparation() {
    // Ant collision radius - ants cannot overlap within this distance
    const double antRadius = 0.35;
    const double minSpacing =
        antRadius * 2; // Two ants touching = 0.7 cells apart
    const double minSpacingSq = minSpacing * minSpacing;

    // Return lists to pool and clear spatial hash
    for (final list in _spatialHash.values) {
      list.clear();
      _spatialHashListPool.add(list);
    }
    _spatialHash.clear();
    _separationAdjustments.clear();

    // Build spatial hash - reuse pooled lists
    for (final ant in ants.toList()) {
      if (ant.isDead ||
          ant.caste == AntCaste.larva ||
          ant.caste == AntCaste.queen ||
          ant.caste == AntCaste.egg) {
        continue;
      }
      final gx = ant.position.x.floor();
      final gy = ant.position.y.floor();
      if (!world.isInsideIndex(gx, gy)) {
        continue;
      }
      final key = world.index(gx, gy);
      final list = _spatialHash.putIfAbsent(key, () {
        return _spatialHashListPool.isNotEmpty
            ? _spatialHashListPool.removeLast()
            : <Ant>[];
      });
      list.add(ant);
    }

    if (_spatialHash.isEmpty) {
      return;
    }

    // Check each cell and its neighbors
    for (final entry in _spatialHash.entries) {
      final cellIdx = entry.key;
      final cellX = cellIdx % world.cols;
      final cellY = cellIdx ~/ world.cols;
      final cellAnts = entry.value;

      // Check against ants in same cell and adjacent cells
      for (var dx = 0; dx <= 1; dx++) {
        for (var dy = (dx == 0 ? 0 : -1); dy <= 1; dy++) {
          final nx = cellX + dx;
          final ny = cellY + dy;
          if (!world.isInsideIndex(nx, ny)) continue;

          final neighborKey = world.index(nx, ny);
          final neighborAnts = _spatialHash[neighborKey];
          if (neighborAnts == null) continue;

          final isSameCell = (dx == 0 && dy == 0);

          for (var i = 0; i < cellAnts.length; i++) {
            final a = cellAnts[i];
            final startJ = isSameCell ? i + 1 : 0;

            for (var j = startJ; j < neighborAnts.length; j++) {
              final b = neighborAnts[j];
              if (a == b) continue;

              final ddx = a.position.x - b.position.x;
              final ddy = a.position.y - b.position.y;
              final distSq = ddx * ddx + ddy * ddy;

              if (distSq >= minSpacingSq) continue;

              // Ants are overlapping - push them apart
              if (distSq < 1e-6) {
                final jitter = 0.15;
                final angle = _rng.nextDouble() * math.pi * 2;
                final pushX = math.cos(angle) * jitter;
                final pushY = math.sin(angle) * jitter;
                _accumulateAdjustment(_separationAdjustments, a, pushX, pushY);
                _accumulateAdjustment(
                  _separationAdjustments,
                  b,
                  -pushX,
                  -pushY,
                );
                // Trigger pause on heavy collision
                a.triggerCollisionPause();
                b.triggerCollisionPause();
                continue;
              }

              final dist = math.sqrt(distSq);
              final overlap = minSpacing - dist;
              final pushStrength = overlap * 0.6;
              final invDist = 1 / dist;
              final pushX = ddx * invDist * pushStrength;
              final pushY = ddy * invDist * pushStrength;

              _accumulateAdjustment(_separationAdjustments, a, pushX, pushY);
              _accumulateAdjustment(_separationAdjustments, b, -pushX, -pushY);

              // Trigger pause if significant overlap
              if (overlap > minSpacing * 0.3) {
                a.triggerCollisionPause();
                b.triggerCollisionPause();
              }
            }
          }
        }
      }
    }

    // Apply adjustments
    for (final entry in _separationAdjustments.entries) {
      final ant = entry.key;
      final delta = entry.value;

      var newX = (ant.position.x + delta.x).clamp(1.0, world.cols - 2.0);
      var newY = (ant.position.y + delta.y).clamp(1.0, world.rows - 2.0);

      final gx = newX.floor();
      final gy = newY.floor();
      if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
        ant.position.setValues(newX.toDouble(), newY.toDouble());
      }
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

    // Reuse spatial hash - return lists to pool and clear
    for (final list in _spatialHash.values) {
      list.clear();
      _spatialHashListPool.add(list);
    }
    _spatialHash.clear();

    // Build spatial hash for O(n) combat detection instead of O(n²)
    for (final ant in ants.toList()) {
      if (ant.isDead ||
          ant.caste == AntCaste.larva ||
          ant.caste == AntCaste.egg) {
        continue;
      }
      final gx = ant.position.x.floor();
      final gy = ant.position.y.floor();
      if (!world.isInsideIndex(gx, gy)) {
        continue;
      }
      final key = world.index(gx, gy);
      final list = _spatialHash.putIfAbsent(key, () {
        return _spatialHashListPool.isNotEmpty
            ? _spatialHashListPool.removeLast()
            : <Ant>[];
      });
      list.add(ant);
    }

    final deadAnts = <Ant>{};
    final checkedPairs = <int>{};

    // Only check ants in same cell and adjacent cells
    for (final entry in _spatialHash.entries) {
      final cellIdx = entry.key;
      final cellX = cellIdx % world.cols;
      final cellY = cellIdx ~/ world.cols;

      // Check this cell and neighbors
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final nx = cellX + dx;
          final ny = cellY + dy;
          if (!world.isInsideIndex(nx, ny)) continue;
          final neighborKey = world.index(nx, ny);
          final neighbors = _spatialHash[neighborKey];
          if (neighbors == null) continue;

          for (final a in entry.value) {
            if (a.isDead || deadAnts.contains(a)) continue;

            for (final b in neighbors) {
              if (a == b || b.isDead || deadAnts.contains(b)) continue;
              if (a.colonyId == b.colonyId) continue;

              // Avoid checking same pair twice
              final pairKey = a.id < b.id
                  ? a.id * 100000 + b.id
                  : b.id * 100000 + a.id;
              if (checkedPairs.contains(pairKey)) continue;
              checkedPairs.add(pairKey);

              final distSq = a.position.distanceToSquared(b.position);
              if (distSq <= fightRadiusSq) {
                final aWillFight = _rng.nextDouble() < a.aggression;
                final bWillFight = _rng.nextDouble() < b.aggression;

                if (aWillFight || bWillFight) {
                  final damageToA = _computeDamage(b, a);
                  final damageToB = _computeDamage(a, b);
                  a.applyDamage(damageToA);
                  b.applyDamage(damageToB);

                  // Winner picks up dead enemy as food
                  if (a.isDead && !b.isDead && !b.hasFood) {
                    deadAnts.add(a);
                    // QUEEN DEATH: Check for princess succession before takeover
                    if (a.caste == AntCaste.queen) {
                      _handleQueenDeath(a.colonyId, b.colonyId);
                    }
                    b.pickUpFood(); // Eat the enemy!
                  } else if (b.isDead && !a.isDead && !a.hasFood) {
                    deadAnts.add(b);
                    // QUEEN DEATH: Check for princess succession before takeover
                    if (b.caste == AntCaste.queen) {
                      _handleQueenDeath(b.colonyId, a.colonyId);
                    }
                    a.pickUpFood(); // Eat the enemy!
                  } else {
                    if (a.isDead) {
                      deadAnts.add(a);
                      if (a.caste == AntCaste.queen && !b.isDead) {
                        _handleQueenDeath(a.colonyId, b.colonyId);
                      }
                    }
                    if (b.isDead) {
                      deadAnts.add(b);
                      if (b.caste == AntCaste.queen && !a.isDead) {
                        _handleQueenDeath(b.colonyId, a.colonyId);
                      }
                    }
                  }
                }
              }
            }
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
    // Don't remove queens, princesses, larvae, or eggs - they don't move much by design
    final stuckAnts = ants
        .where(
          (a) =>
              a.isStuck &&
              a.caste != AntCaste.queen &&
              a.caste != AntCaste.princess &&
              a.caste != AntCaste.larva &&
              a.caste != AntCaste.egg,
        )
        .toList();
    if (stuckAnts.isNotEmpty) {
      ants.removeWhere(stuckAnts.contains);
      _updateAntCount();
    }
  }

  void _removeOldAnts() {
    // Remove ants that have died of old age (natural lifespan)
    // This controls population growth and ensures continuous turnover
    final oldAnts = ants.where((a) => a.isDyingOfOldAge).toList();
    if (oldAnts.isNotEmpty) {
      for (final ant in oldAnts) {
        if (ant.caste == AntCaste.queen) {
          _handleInternalQueenDeath(ant.colonyId);
        }
      }
      ants.removeWhere(oldAnts.contains);
      _updateAntCount();
    }
  }

  /// Handle queen death - check for princess succession before takeover
  void _handleQueenDeath(int defeatedColonyId, int conquerorColonyId) {
    // Check if the defeated colony has a princess to take over
    final princess = ants
        .where(
          (ant) =>
              ant.colonyId == defeatedColonyId &&
              ant.caste == AntCaste.princess &&
              !ant.isDead,
        )
        .firstOrNull;

    if (princess != null) {
      // Princess succession! Colony survives with new queen
      princess.promoteToQueen();
      // ignore: avoid_print
      print(
        'PRINCESS SUCCESSION: Colony $defeatedColonyId princess became queen!',
      );
    } else {
      // No princess available - colony is taken over
      _handleColonyTakeover(defeatedColonyId, conquerorColonyId);
    }
  }

  void _handleInternalQueenDeath(int colonyId) {
    final princess = ants
        .where(
          (ant) =>
              ant.colonyId == colonyId &&
              ant.caste == AntCaste.princess &&
              !ant.isDead,
        )
        .firstOrNull;
    if (princess != null) {
      princess.promoteToQueen();
      return;
    }
    _spawnEmergencyQueen(colonyId);
  }

  void _checkColonyResources() {
    for (var colonyId = 0; colonyId < config.colonyCount; colonyId++) {
      final storedFood = _colonyFood[colonyId];
      final nearbyFood = _estimateFoodNearNest(colonyId, config.nestRadius * 4);
      final threshold = config.foodPerNewAnt * 2;
      if (storedFood < threshold && nearbyFood < WorldGrid.defaultFoodPerCell) {
        _spawnEmergencyFoodNearNest(colonyId);
      }
    }
  }

  int _estimateFoodNearNest(int colonyId, double radius) {
    final nest = world.getNestPosition(colonyId);
    final radiusSq = radius * radius;
    var total = 0;
    for (final idx in world.foodCells) {
      final x = idx % world.cols;
      final y = idx ~/ world.cols;
      final dx = (x + 0.5) - nest.x;
      final dy = (y + 0.5) - nest.y;
      if (dx * dx + dy * dy <= radiusSq) {
        total += world.foodAmount[idx];
      }
    }
    return total;
  }

  void _spawnEmergencyFoodNearNest(int colonyId) {
    final nest = world.getNestPosition(colonyId);
    final angle = _rng.nextDouble() * math.pi * 2;
    final distance = config.nestRadius + 3 + _rng.nextDouble() * 4;
    final position = Vector2(
      (nest.x + math.cos(angle) * distance).clamp(2, world.cols - 3),
      (nest.y + math.sin(angle) * distance).clamp(2, world.rows - 3),
    );
    world.placeFood(position, 1, amount: WorldGrid.defaultFoodPerCell ~/ 3);
  }

  void _spawnEmergencyQueen(int colonyId) {
    final nest = world.getNestPosition(colonyId);
    final offset = Vector2(
      (_rng.nextDouble() - 0.5) * 2,
      (_rng.nextDouble() - 0.5) * 2,
    );
    ants.add(
      Ant(
        startPosition: nest + offset,
        angle: _rng.nextDouble() * math.pi * 2,
        energy: config.energyCapacity,
        rng: _rng,
        caste: AntCaste.queen,
        colonyId: colonyId,
      ),
    );
    _updateAntCount();
  }

  /// Handle colony takeover when a queen dies in combat.
  /// All ants from the defeated colony join the conquering colony.
  /// The defeated colony's nest becomes a secondary base for the conqueror.
  void _handleColonyTakeover(int defeatedColonyId, int conquerorColonyId) {
    // Count ants being converted
    var convertedCount = 0;

    // Convert all living ants from defeated colony to conqueror's colony
    for (final ant in ants.toList()) {
      if (ant.colonyId == defeatedColonyId && !ant.isDead) {
        ant.colonyId = conquerorColonyId;
        // Reset their state to forage for the new colony
        if (ant.caste == AntCaste.worker || ant.caste == AntCaste.soldier) {
          ant.state = AntState.forage;
        }
        convertedCount++;
      }
    }

    // Transfer food reserves from defeated colony to conqueror
    if (defeatedColonyId < _colonyFood.length &&
        conquerorColonyId < _colonyFood.length) {
      _colonyFood[conquerorColonyId] += _colonyFood[defeatedColonyId];
      _colonyFood[defeatedColonyId] = 0;
    }

    // Transfer queued ants from defeated colony to conqueror
    if (defeatedColonyId < _colonyQueuedAnts.length &&
        conquerorColonyId < _colonyQueuedAnts.length) {
      _colonyQueuedAnts[conquerorColonyId] +=
          _colonyQueuedAnts[defeatedColonyId];
      _colonyQueuedAnts[defeatedColonyId] = 0;
    }

    // Update displays
    _updateAntCount();

    // Track colony takeover - major game event
    AnalyticsService.instance.logColonyTakeover(
      winnerColonyId: conquerorColonyId,
      defeatedColonyId: defeatedColonyId,
      convertedAnts: convertedCount,
      daysPassed: daysPassed.value,
    );

    // Log the takeover (could add a notification system later)
    // ignore: avoid_print
    print(
      'COLONY TAKEOVER: Colony $conquerorColonyId conquered Colony $defeatedColonyId! ($convertedCount ants converted)',
    );
  }

  /// Queens emit strong pheromones towards reachable food using BFS pathfinding.
  /// Instead of shooting a straight line (which ignores existing tunnels),
  /// the queen finds the actual walkable path to food and deposits pheromones along it.
  /// If no walkable path exists, she emits nothing and lets ants explore/dig naturally.
  void _queenFoodGuidance() {
    if (world.foodCells.isEmpty) return;

    // Use toList() to avoid ConcurrentModificationError if ants list changes
    for (final ant in ants.toList()) {
      if (ant.caste != AntCaste.queen || ant.isDead) continue;

      final qx = ant.position.x.floor();
      final qy = ant.position.y.floor();

      // Use BFS to find shortest walkable path to any food (longer range)
      final path = world.computePathToFood(qx, qy, maxLength: 60);

      if (path != null && path.isNotEmpty) {
        // Deposit pheromones along actual walkable path
        const pheromoneStrength = 0.7;
        for (var i = 0; i < path.length && i < 30; i++) {
          final idx = path[i];
          final x = idx % world.cols;
          final y = idx ~/ world.cols;
          // Decay strength with distance - stronger near queen, weaker near food
          final strength = pheromoneStrength * (1.0 - i / 40.0);
          world.depositFoodPheromone(x, y, strength, ant.colonyId);
        }
      }
      // No walkable path: emit nothing, let ants explore/dig using food scent diffusion
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
      'dirtTypes': _encodeUint8(Uint8List.fromList(world.dirtTypes)),
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
      'rooms': world.rooms.map((r) => r.toJson()).toList(),
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

enum _BuildTaskKind { room, reinforce, defense }

class _BuildTask {
  _BuildTask({
    required this.id,
    required this.kind,
    required this.colonyId,
    required this.targetLocation,
    required this.radius,
    this.roomType,
    this.emergency = false,
  });

  final int id;
  final _BuildTaskKind kind;
  final int colonyId;
  final Vector2 targetLocation;
  final double radius;
  final RoomType? roomType;
  bool emergency;
  bool inProgress = false;
  int assignedBuilderId = -1;
}
