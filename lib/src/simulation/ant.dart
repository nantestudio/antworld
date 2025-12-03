import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

enum AntState { forage, returnHome, rest }

/// Ant castes with different roles and abilities
enum AntCaste {
  worker, // Basic forager/digger
  soldier, // Combat-focused, patrols and defends
  nurse, // Stays in nest, cares for larvae
  drone, // Male, reproductive only
  princess, // Future queen, waits for succession
  queen, // Produces eggs, stays in nest center
  larva, // Immobile, needs feeding to mature
  egg, // Immobile, hatches into larva after development
  builder, // Constructs rooms and defensive walls
}

/// Builder-specific tasks coordinated by the colony
enum BuilderTask {
  idle,
  buildingRoom,
  reinforcingWall,
  emergencyDefense,
  constructingBlueprint,
  returningHome,
}

/// Caste-specific stats and modifiers
class CasteStats {
  const CasteStats({
    required this.speedMultiplier,
    required this.baseHp,
    required this.baseAttack,
    required this.baseDefense,
    required this.canForage,
    required this.explorerRange,
    required this.baseAggression,
  });

  final double speedMultiplier;
  final double baseHp;
  final double baseAttack;
  final double baseDefense;
  final bool canForage;
  final (double, double) explorerRange; // min, max explorer tendency
  final double baseAggression; // 0.0-1.0, likelihood to initiate combat

  static const Map<AntCaste, CasteStats> stats = {
    AntCaste.worker: CasteStats(
      speedMultiplier: 1.0,
      baseHp: 100,
      baseAttack: 3, // weaker in combat
      baseDefense: 1, // less defensive
      canForage: true,
      explorerRange: (0.0, 0.3),
      baseAggression: 0.1, // rarely fights, flees instead
    ),
    AntCaste.soldier: CasteStats(
      speedMultiplier: 0.9, // faster than before
      baseHp: 150,
      baseAttack: 25, // much stronger attack
      baseDefense: 12, // better defense
      canForage: false,
      explorerRange: (0.1, 0.2),
      baseAggression: 0.95, // almost always fights
    ),
    AntCaste.nurse: CasteStats(
      speedMultiplier: 0.7,
      baseHp: 80,
      baseAttack: 2,
      baseDefense: 1,
      canForage: false,
      explorerRange: (0.0, 0.05),
      baseAggression: 0.1, // Very passive, flees
    ),
    AntCaste.drone: CasteStats(
      speedMultiplier: 1.1,
      baseHp: 60,
      baseAttack: 1,
      baseDefense: 1,
      canForage: false,
      explorerRange: (0.0, 0.1),
      baseAggression: 0.05, // Almost never fights
    ),
    AntCaste.princess: CasteStats(
      speedMultiplier: 0.4,
      baseHp: 300,
      baseAttack: 2,
      baseDefense: 8,
      canForage: false,
      explorerRange: (0.0, 0.0),
      baseAggression: 0.0, // Never initiates combat, future queen
    ),
    AntCaste.queen: CasteStats(
      speedMultiplier: 0.3,
      baseHp: 500,
      baseAttack: 3,
      baseDefense: 10,
      canForage: false,
      explorerRange: (0.0, 0.0),
      baseAggression: 0.0, // Never initiates combat
    ),
    AntCaste.larva: CasteStats(
      speedMultiplier: 0.05, // Very slow wiggling
      baseHp: 50,
      baseAttack: 0,
      baseDefense: 0,
      canForage: false,
      explorerRange: (0.0, 0.0),
      baseAggression: 0.0, // Defenseless
    ),
    AntCaste.egg: CasteStats(
      speedMultiplier: 0.0,
      baseHp: 20,
      baseAttack: 0,
      baseDefense: 0,
      canForage: false,
      explorerRange: (0.0, 0.0),
      baseAggression: 0.0, // Completely defenseless
    ),
    AntCaste.builder: CasteStats(
      speedMultiplier: 0.6, // Deliberate movement
      baseHp: 70, // Frailer than workers
      baseAttack: 1, // Poor fighters
      baseDefense: 2,
      canForage: false, // Construction-only caste
      explorerRange: (0.0, 0.05), // Stays near colony
      baseAggression: 0.05, // Avoids combat
    ),
  };
}

const int _builderDigStepMultiplier = 8;

class Ant {
  static int _nextId = 1;

  /// Reset ID counter (call when starting new simulation)
  static void resetIdCounter() => _nextId = 1;

  Ant({
    required Vector2 startPosition,
    required this.angle,
    required this.energy,
    required math.Random rng,
    this.caste = AntCaste.worker,
    this.colonyId = 0,
  }) : id = _nextId++,
       position = startPosition.clone(),
       _explorerTendency = _generateExplorerTendency(caste, rng),
       aggression = CasteStats.stats[caste]!.baseAggression,
       attack = CasteStats.stats[caste]!.baseAttack,
       defense = CasteStats.stats[caste]!.baseDefense,
       maxHp = CasteStats.stats[caste]!.baseHp,
       hp = CasteStats.stats[caste]!.baseHp;

  Ant.rehydrated({
    required this.id,
    required Vector2 position,
    required this.angle,
    required this.state,
    required bool carryingFood,
    required this.energy,
    AntState? stateBeforeRest,
    double explorerTendency = 0.0,
    this.caste = AntCaste.worker,
    this.colonyId = 0,
    this.aggression = 0.2,
    required this.attack,
    required this.defense,
    required double maxHpValue,
    double? hp,
    double growthProgress = 0.0,
    int carryingLarvaId = -1,
    int carryingEggId = -1,
    double eggLayTimer = 0.0,
    double age = 0.0,
    BuilderTask builderTask = BuilderTask.idle,
    Vector2? builderTarget,
    double builderTargetRadius = 0.0,
    int activeBuilderTaskId = -1,
    bool builderEmergencyTask = false,
  }) : position = position.clone(),
       _carryingFood = carryingFood,
       _stateBeforeRest = stateBeforeRest,
       _explorerTendency = explorerTendency,
       maxHp = maxHpValue,
       hp = (hp ?? maxHpValue).clamp(0, maxHpValue),
       _growthProgress = growthProgress,
       _carryingLarvaId = carryingLarvaId,
       _carryingEggId = carryingEggId,
       _eggLayTimer = eggLayTimer,
       _age = age,
       _builderTask = builderTask,
       _builderTarget = builderTarget?.clone(),
       _builderTargetRadius = builderTargetRadius,
       _activeBuilderTaskId = activeBuilderTaskId,
       _builderEmergencyTask = builderEmergencyTask;

  static double _generateExplorerTendency(AntCaste caste, math.Random rng) {
    final range = CasteStats.stats[caste]!.explorerRange;
    return range.$1 + rng.nextDouble() * (range.$2 - range.$1);
  }

  final int id;
  final Vector2 position;
  double angle;
  AntState state = AntState.forage;
  AntState? _stateBeforeRest;
  double energy;
  bool _carryingFood = false;
  int _consecutiveRockHits = 0;
  int _collisionCooldown = 0;
  double _speedMultiplier = 1.0;
  final double _explorerTendency; // 0.0-1.0, personality trait for exploration
  AntCaste caste; // Can change on promotion (princess -> queen)
  int
  colonyId; // 0-3 - which colony this ant belongs to (can change on takeover)
  double aggression; // 0.0-1.0, likelihood to initiate combat
  double attack;
  double defense;
  double maxHp;
  double hp;
  bool _needsRest = false;
  Vector2? _restingSpot;

  // Egg/Larva growth (used when caste == egg or larva)
  double _growthProgress = 0.0;
  static const double _eggHatchTime =
      20.0; // seconds for egg to hatch into larva (longer development)
  static const double _growthTimeToMature =
      60.0; // seconds for larva to mature into adult (longer growth)

  // Age and lifespan (in seconds)
  double _age = 0.0;
  // Max lifespan per caste (in game seconds)
  static const Map<AntCaste, double> _maxLifespan = {
    AntCaste.worker: 240.0, // 4 minutes - faster turnover
    AntCaste.soldier: 180.0, // 3 minutes - combat life is short
    AntCaste.nurse: 300.0, // 5 minutes
    AntCaste.drone: 150.0, // 2.5 minutes (short-lived)
    AntCaste.queen: 1800.0, // 30 minutes - queens live much longer
    AntCaste.princess: 600.0, // 10 minutes - waiting to become queen
    AntCaste.larva: 120.0, // 2 minutes (will mature before this)
    AntCaste.egg: 60.0, // 1 minute (will hatch before this)
    AntCaste.builder: 300.0, // 5 minutes - same as nurse
  };

  // Nurse carrying larva (reference by ID, -1 = not carrying)
  int _carryingLarvaId = -1;
  // Nurse carrying egg (reference by ID, -1 = not carrying)
  int _carryingEggId = -1;

  // Queen egg laying timer
  double _eggLayTimer = 0.0;
  static const double _eggLayInterval =
      45.0; // seconds between laying eggs (less frequent)

  // Stuck detection
  final Vector2 _lastPosition = Vector2.zero();
  double _stuckTime = 0;
  static const double _stuckThreshold = 30.0; // seconds before considered stuck

  // Fog of war - track last cell revealed to avoid redundant updates
  int _lastRevealCellX = -1;
  int _lastRevealCellY = -1;
  static const double _moveThreshold =
      0.5; // minimum distance to count as moved

  // Collision pause - ant stops briefly after hitting something
  double _collisionPauseTimer = 0;
  static const double _collisionPauseDuration =
      0.8; // seconds to pause after collision

  // Defense mode - soldier is actively defending colony from intruders
  bool _isDefending = false;

  bool get hasFood => _carryingFood;
  bool get isDead => hp <= 0;
  bool get isStuck => _stuckTime >= _stuckThreshold;
  double get stuckTime => _stuckTime;
  double get explorerTendency => _explorerTendency;
  bool get isExplorer => _explorerTendency > 0.15; // High tendency = explorer
  bool get needsRest => _needsRest;
  bool get isPaused => _collisionPauseTimer > 0;
  bool get isDefending => _isDefending;
  AntState? get stateBeforeRest => _stateBeforeRest;
  double get casteSpeedMultiplier => CasteStats.stats[caste]!.speedMultiplier;
  bool get canForage => CasteStats.stats[caste]!.canForage;
  double get growthProgress => _growthProgress;
  bool get isCarryingLarva => _carryingLarvaId >= 0;
  int get carryingLarvaId => _carryingLarvaId;
  bool get isCarryingEgg => _carryingEggId >= 0;
  int get carryingEggId => _carryingEggId;
  bool get isReadyToHatch =>
      caste == AntCaste.egg && _growthProgress >= _eggHatchTime;
  bool get isReadyToMature =>
      caste == AntCaste.larva && _growthProgress >= _growthTimeToMature;
  bool get wantsToLayEgg =>
      caste == AntCaste.queen && _eggLayTimer >= _eggLayInterval;
  double get age => _age;
  double get maxLifespan => _maxLifespan[caste] ?? 300.0;
  bool get isDyingOfOldAge => _age >= maxLifespan;

  /// Get progress as 0.0-1.0 for display purposes
  double get developmentProgress {
    if (caste == AntCaste.egg) {
      return (_growthProgress / _eggHatchTime).clamp(0.0, 1.0);
    } else if (caste == AntCaste.larva) {
      return (_growthProgress / _growthTimeToMature).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  void applyDamage(double amount) {
    hp = math.max(0, hp - amount);
  }

  /// Trigger a brief pause after colliding with another ant
  void triggerCollisionPause() {
    // Only set if not already paused (avoid resetting timer)
    if (_collisionPauseTimer <= 0) {
      _collisionPauseTimer =
          _collisionPauseDuration * 0.5; // Shorter pause for ant collisions
    }
  }

  bool update(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed, {
    Vector2? attackTarget,
  }) {
    if (dt == 0) return false;

    // Track age for lifespan/natural death
    _age += dt;

    // Fog of war - reveal area around ant when moving to new cell
    // Skip for eggs/larvae (immobile)
    if (caste != AntCaste.egg && caste != AntCaste.larva) {
      final cellX = position.x.floor();
      final cellY = position.y.floor();
      // Only reveal if moved to a different cell (performance optimization)
      if (cellX != _lastRevealCellX || cellY != _lastRevealCellY) {
        world.revealArea(cellX, cellY);
        _lastRevealCellX = cellX;
        _lastRevealCellY = cellY;
      }
    }

    // Handle collision pause - ant stops briefly after hitting something
    if (_collisionPauseTimer > 0) {
      _collisionPauseTimer -= dt;
      if (_collisionPauseTimer > 0) {
        return false; // Still paused, don't move
      }
    }

    // Stuck detection - track if ant has moved (skip for resting ants)
    if (state != AntState.rest) {
      final distMoved = position.distanceTo(_lastPosition);
      if (distMoved < _moveThreshold) {
        _stuckTime += dt;
        // Deposit blocked pheromone when stuck for a while (but before garbage collection)
        if (_stuckTime > 5.0 && _stuckTime < _stuckThreshold) {
          final gx = position.x.floor();
          final gy = position.y.floor();
          if (world.isInsideIndex(gx, gy)) {
            world.depositBlockedPheromone(gx, gy, 0.1 * dt);
          }
        }
      } else {
        _stuckTime = 0;
        _lastPosition.setFrom(position);
      }
    } else {
      _stuckTime = 0; // Reset when resting
    }

    // Caste-specific behaviors
    switch (caste) {
      case AntCaste.egg:
        return _updateEgg(dt);
      case AntCaste.larva:
        return _updateLarva(dt, config, world, rng);
      case AntCaste.queen:
        return _updateQueen(dt, config, world, rng);
      case AntCaste.princess:
        return _updatePrincess(dt, config, world, rng);
      case AntCaste.nurse:
        return _updateNurse(dt, config, world, rng, antSpeed);
      case AntCaste.soldier:
        return _updateSoldier(dt, config, world, rng, antSpeed, attackTarget);
      case AntCaste.builder:
        return _updateBuilder(dt, config, world, rng, antSpeed);
      case AntCaste.worker:
      case AntCaste.drone:
        // Workers and drones use standard foraging behavior below
        break;
    }

    final restEnabled = config.restEnabled;

    if (!restEnabled && state == AntState.rest) {
      _wakeFromRest();
    }

    if (restEnabled && state == AntState.rest) {
      _recoverEnergy(dt, config);
      return false;
    }

    if (restEnabled) {
      energy -= config.energyDecayPerSecond * dt;
      if (energy <= 0) {
        if (!_needsRest) {
          _stateBeforeRest = state;
          _needsRest = true;
          _assignRestLocation(world);
        }
        state = AntState.returnHome;
        energy = config.digEnergyCost * 1.5;
      }
    } else {
      energy = config.energyCapacity;
    }

    // Occasionally adjust speed for natural variation (5% chance per frame)
    if (rng.nextDouble() < 0.05) {
      _speedMultiplier = 0.7 + rng.nextDouble() * 0.6; // 0.7 to 1.3x speed
    }

    _steer(config, world, rng);

    final distance = antSpeed * dt * _speedMultiplier;
    final vx = math.cos(angle) * distance;
    final vy = math.sin(angle) * distance;

    final nextX = position.x + vx;
    final nextY = position.y + vy;

    // Check path for collisions using raycast
    final collision = _checkPathCollision(
      position.x,
      position.y,
      nextX,
      nextY,
      world,
    );

    if (collision != null) {
      // Hit an obstacle along the path
      final hitBlock = collision.cellType;
      final hitX = collision.cellX;
      final hitY = collision.cellY;

      if (hitBlock == CellType.food) {
        if (!hasFood) {
          // Pick up food and immediately turn toward home
          _carryingFood = true;
          state = AntState.returnHome;
          world.consumeFood(hitX, hitY);
          _consecutiveRockHits = 0;

          // Turn toward nest immediately (not just a small rotation)
          final nestPos = world.getNestPosition(colonyId);
          final toNest = nestPos - position;
          if (toNest.length2 > 0) {
            angle = math.atan2(toNest.y, toNest.x);
            // Add small random variation so ants don't all take exact same path
            angle += (rng.nextDouble() - 0.5) * 0.3;
          }
          return false;
        } else {
          // Already carrying food - bounce away from this food block
          // Turn around (opposite direction) with some randomness
          angle += math.pi + (rng.nextDouble() - 0.5) * 0.6;
          _consecutiveRockHits = 0;
          return false;
        }
      } else if (hitBlock == CellType.dirt) {
        _dig(world, hitX, hitY, config);
        angle += math.pi / 2 + (rng.nextDouble() - 0.5) * 0.6;
        _consecutiveRockHits = 0; // Reset rock hit counter on dirt collision
        // Short pause after digging
        _collisionPauseTimer = _collisionPauseDuration * 0.3;
        return false;
      } else if (hitBlock == CellType.rock) {
        // Deposit blocked pheromone to warn other ants about this obstacle
        world.depositBlockedPheromone(hitX, hitY, 0.3);

        // Only 10% of ants try to navigate around obstacles intelligently
        if (rng.nextDouble() < 0.10) {
          _consecutiveRockHits++;
          _handleRockCollision(rng);
          _collisionCooldown =
              10; // Don't allow small steering adjustments for 10 frames
        } else {
          // 90% just bounce back
          angle += math.pi + (rng.nextDouble() - 0.5) * 0.3;
        }
        // Pause after hitting rock
        _collisionPauseTimer = _collisionPauseDuration;
        return false;
      }
    }

    final gx = nextX.floor();
    final gy = nextY.floor();
    final walkable =
        world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy);
    if (!walkable) {
      _rotateAway(rng);
      return false;
    }

    var steppedOnFood = false;
    final destBlock = world.cellTypeAt(gx, gy);
    if (destBlock == CellType.food && !hasFood) {
      position.setValues(gx + 0.5, gy + 0.5);
      if (world.consumeFood(gx, gy)) {
        _carryingFood = true;
        state = AntState.returnHome;
        angle += config.foodPickupRotation + (rng.nextDouble() - 0.5) * 0.2;
        _collisionPauseTimer = math.max(_collisionPauseTimer, 0.05);
        steppedOnFood = true;
      }
    } else {
      position.setValues(nextX, nextY);
    }

    // Successfully moved - reset collision tracking
    if (_collisionCooldown > 0) {
      _collisionCooldown--;
    }
    if (_consecutiveRockHits > 0) {
      _consecutiveRockHits = 0; // Reset when moving freely
    }

    final depositX = position.x.floor();
    final depositY = position.y.floor();
    if (world.isInsideIndex(depositX, depositY)) {
      if (hasFood) {
        // Vary deposit strength ±20% for natural trail variation
        final strength =
            config.foodDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositFoodPheromone(depositX, depositY, strength, colonyId);
      } else {
        final strength =
            config.homeDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositHomePheromone(depositX, depositY, strength, colonyId);
      }
    }

    final myNest = world.getNestPosition(colonyId);
    final dropRoom = world.getFoodRoom(colonyId);
    final dropCenter = dropRoom?.center ?? myNest;
    final dropRadius = dropRoom != null
        ? dropRoom.radius + 0.5
        : config.nestRadius + 0.5;
    var deliveredFood = false;
    if (position.distanceTo(dropCenter) < dropRadius && hasFood) {
      _carryingFood = false;
      deliveredFood = true;
      angle += math.pi;
    }

    if (_needsRest) {
      final target = _restingSpot ?? myNest;
      final restRadius = _restingSpot != null
          ? config.nestRadius * 0.4
          : config.nestRadius + 0.5;
      if (position.distanceTo(target) < restRadius) {
        state = AntState.forage;
        _enterRest();
        return deliveredFood || steppedOnFood;
      }
    }

    if (deliveredFood || steppedOnFood) {
      state = AntState.forage;
      return deliveredFood || steppedOnFood;
    }

    return false;
  }

  void _steer(SimulationConfig config, WorldGrid world, math.Random rng) {
    // Skip steering during collision cooldown to commit to avoidance direction
    if (_collisionCooldown > 0) {
      return;
    }

    final behavior = state == AntState.rest && _stateBeforeRest != null
        ? _stateBeforeRest!
        : state;

    if (behavior == AntState.returnHome || _needsRest || hasFood) {
      // PRIORITY 1: Food-carrying ants go directly to food storage room
      // This prevents congestion at the queen's location
      if (hasFood) {
        final foodRoom = world.getFoodRoom(colonyId);
        final target = foodRoom?.center ?? world.getNestPosition(colonyId);
        final toTarget = target - position;
        if (toTarget.length2 > 0.01) {
          final desired = math.atan2(toTarget.y, toTarget.x);
          final delta = _normalizeAngle(desired - angle);
          angle += delta.clamp(-0.5, 0.5) * (0.7 + rng.nextDouble() * 0.2);
          angle += (rng.nextDouble() - 0.5) * 0.05; // Small noise for spread
        }
        return;
      }

      // PRIORITY 2: Resting ants (without food) go to barracks
      if (_needsRest && _restingSpot != null) {
        final desired = math.atan2(
          _restingSpot!.y - position.y,
          _restingSpot!.x - position.x,
        );
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.5, 0.5) * (0.6 + rng.nextDouble() * 0.2);
        return;
      }

      // PRIORITY 3: Follow home pheromone trails (for non-food returnHome)
      // This creates consistent "ant highways" where ants return on the same path
      final sensorRight = _sense(
        angle + config.sensorAngle,
        config,
        world,
        rng,
      );
      final sensorFront = _sense(angle, config, world, rng);
      final sensorLeft = _sense(angle - config.sensorAngle, config, world, rng);

      final maxSignal = math.max(
        sensorFront,
        math.max(sensorLeft, sensorRight),
      );
      if (maxSignal > 0.05) {
        // Follow home pheromone gradient - stay on the trail
        if (sensorFront >= sensorLeft && sensorFront >= sensorRight) {
          // Front strongest - go straight with tiny noise
          angle += (rng.nextDouble() - 0.5) * 0.05;
        } else if (sensorLeft > sensorRight) {
          // Turn left toward stronger home scent
          angle -= (rng.nextDouble() * 0.15 + 0.1);
        } else {
          // Turn right toward stronger home scent
          angle += (rng.nextDouble() * 0.15 + 0.1);
        }
        return;
      }

      // PRIORITY 4: No pheromone trail - use BFS pathfinding
      final dir = world.directionToNest(position, colonyId: colonyId);
      if (dir != null && dir.length2 > 0.0001) {
        final desiredAngle = math.atan2(dir.y, dir.x);
        final delta = _normalizeAngle(desiredAngle - angle);
        angle += delta.clamp(-0.5, 0.5) * (0.7 + rng.nextDouble() * 0.2);
        angle += (rng.nextDouble() - 0.5) * 0.05;
        return;
      }

      // PRIORITY 5: No BFS path - fall back to direct vector toward nest
      final myNest = world.getNestPosition(colonyId);
      final nestDir = myNest - position;
      if (nestDir.length2 > 0) {
        final desiredAngle = math.atan2(nestDir.y, nestDir.x);
        final delta = _normalizeAngle(desiredAngle - angle);
        angle += delta.clamp(-0.5, 0.5) * 0.6;
        angle += (rng.nextDouble() - 0.5) * 0.1;
      }
      return;
    }

    // Random exploration: based on explorer tendency (personality trait)
    // Higher tendency = more likely to ignore pheromones and wander
    // Reduced from 1-51% to 0.5-10% for more focused behavior
    final exploreChance = 0.005 + _explorerTendency * 0.1;
    if (rng.nextDouble() < exploreChance) {
      angle += (rng.nextDouble() - 0.5) * config.randomTurnStrength * 0.5;
      return; // Skip normal pheromone following
    }

    // Add small random variation to sensor angles (±5% jitter)
    final angleJitter = config.sensorAngle * (rng.nextDouble() - 0.5) * 0.1;
    final sensorRight = _sense(
      angle + config.sensorAngle + angleJitter,
      config,
      world,
      rng,
    );
    final sensorFront = _sense(angle + angleJitter * 0.5, config, world, rng);
    final sensorLeft = _sense(
      angle - config.sensorAngle + angleJitter,
      config,
      world,
      rng,
    );

    // Check if any sensor detected pheromones (value > 0)
    final hasPheromones = sensorFront > 0 || sensorLeft > 0 || sensorRight > 0;
    final maxSignal = math.max(sensorFront, math.max(sensorLeft, sensorRight));

    bool steered = false;
    if (hasPheromones && maxSignal > 0.01) {
      // Follow pheromone gradient
      if (sensorFront >= sensorLeft && sensorFront >= sensorRight) {
        // Front is strongest or equal - go mostly straight with small noise
        angle += (rng.nextDouble() - 0.5) * 0.08;
        steered = true;
      } else if (sensorLeft > sensorRight) {
        // Left is strongest - turn left
        // Mistake chance scales with explorer tendency (3% to 18%)
        final mistakeChance = 0.03 + _explorerTendency * 0.5;
        final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
        angle -= (rng.nextDouble() * 0.15 + 0.08) * mistakeFactor;
        steered = true;
      } else {
        // Right is strongest - turn right
        final mistakeChance = 0.03 + _explorerTendency * 0.5;
        final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
        angle += (rng.nextDouble() * 0.15 + 0.08) * mistakeFactor;
        steered = true;
      }
    }

    // When NO pheromones detected, use direct food sensing to find food
    if (!steered && behavior == AntState.forage) {
      // Always try food sensing when there are no pheromone trails to follow
      final foodTarget = _biasTowardFood(world, config, rng);
      if (foodTarget != null) {
        // Successfully steering toward food
        return;
      }
      // No food in range - moderate wandering to explore (reduced from 0.4)
      angle += (rng.nextDouble() - 0.5) * 0.2;
    } else if (!steered) {
      // Minimal random wandering when no guidance at all
      angle += (rng.nextDouble() - 0.5) * 0.1;
    }
  }

  double _sense(
    double direction,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
  ) {
    final sx = position.x + math.cos(direction) * config.sensorDistance;
    final sy = position.y + math.sin(direction) * config.sensorDistance;
    final gx = sx.floor();
    final gy = sy.floor();

    if (!world.isInsideIndex(gx, gy)) {
      return -1;
    }
    final cellType = world.cellTypeAt(gx, gy);
    if (cellType == CellType.dirt || cellType == CellType.rock) {
      return -1;
    }

    // Check for blocked pheromone - strongly discourages this direction
    final blockedAmount = world.blockedPheromoneAt(gx, gy);
    if (blockedAmount > 0.5) {
      return -0.5; // Treat high blocked areas like obstacles
    }

    final behavior = state == AntState.rest && _stateBeforeRest != null
        ? _stateBeforeRest!
        : state;

    if (behavior == AntState.forage) {
      // Sense own colony's food pheromones (trails to food sources)
      var value = world.foodPheromoneAt(gx, gy, colonyId);

      // Add food scent (diffusing smell from food sources)
      // This strongly guides ants through existing tunnels toward food
      final foodScentValue = world.foodScentAt(gx, gy);
      value += foodScentValue * 5.0; // Food scent is very attractive

      if (world.cellTypeAt(gx, gy) == CellType.food) {
        value += 10;
      }
      // Add perceptual noise: ±15% variation
      value *= (0.85 + rng.nextDouble() * 0.3);
      // Subtract blocked pheromone penalty
      value -= blockedAmount * 2;
      return value;
    }

    // Sense own colony's home pheromones (trails back to nest)
    var value = world.homePheromoneAt(gx, gy, colonyId);
    // Add perceptual noise: ±15% variation
    value *= (0.85 + rng.nextDouble() * 0.3);
    // Subtract blocked pheromone penalty
    value -= blockedAmount * 2;
    return value;
  }

  Vector2? _biasTowardFood(
    WorldGrid world,
    SimulationConfig config,
    math.Random rng,
  ) {
    // Follow food scent gradient - smell spreads through tunnels like gas
    // Sample scent in 3 directions (like pheromone sensors)
    final sensorDist = config.sensorDistance;
    final gx = position.x.floor();
    final gy = position.y.floor();

    // Check if we're standing on or very close to food scent
    final currentScent = world.foodScentAt(gx, gy);
    if (currentScent < 0.001) {
      // No scent here at all - fall back to direct food sensing for very close food
      final target = world.nearestFood(position, 15.0); // Short range fallback
      if (target != null) {
        final desired = math.atan2(
          target.y - position.y,
          target.x - position.x,
        );
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.5, 0.5) * 0.7;
        angle += (rng.nextDouble() - 0.5) * 0.02;
        return target;
      }
      return null;
    }

    // Sample scent in left, front, right directions
    final leftAngle = angle - config.sensorAngle;
    final frontAngle = angle;
    final rightAngle = angle + config.sensorAngle;

    double sampleScent(double dir) {
      final sx = (position.x + math.cos(dir) * sensorDist).floor();
      final sy = (position.y + math.sin(dir) * sensorDist).floor();
      if (!world.isInsideIndex(sx, sy)) return 0;
      if (!world.isWalkableCell(sx, sy)) return -1; // Blocked
      return world.foodScentAt(sx, sy);
    }

    final leftScent = sampleScent(leftAngle);
    final frontScent = sampleScent(frontAngle);
    final rightScent = sampleScent(rightAngle);

    // Find max scent direction (ignore blocked directions)
    final maxScent = [
      leftScent,
      frontScent,
      rightScent,
    ].where((s) => s >= 0).fold(0.0, (a, b) => a > b ? a : b);

    if (maxScent < 0.001) {
      // No scent detected in any direction - wander
      return null;
    }

    // Turn toward strongest scent
    if (frontScent >= leftScent &&
        frontScent >= rightScent &&
        frontScent >= 0) {
      // Front strongest - go mostly straight
      angle += (rng.nextDouble() - 0.5) * 0.05;
    } else if (leftScent > rightScent && leftScent >= 0) {
      // Turn left
      angle -= (rng.nextDouble() * 0.15 + 0.1);
    } else if (rightScent >= 0) {
      // Turn right
      angle += (rng.nextDouble() * 0.15 + 0.1);
    }

    // Return a dummy target to indicate we're following scent
    return Vector2(position.x + math.cos(angle), position.y + math.sin(angle));
  }

  _PathCollision? _checkPathCollision(
    double x0,
    double y0,
    double x1,
    double y1,
    WorldGrid world,
  ) {
    // Traverse the grid cells intersected by the movement ray (Amanatides & Woo).
    final dx = x1 - x0;
    final dy = y1 - y0;
    final distanceSq = dx * dx + dy * dy;

    if (distanceSq < 0.0001) {
      return null; // Not moving enough to matter
    }

    var cellX = x0.floor();
    var cellY = y0.floor();
    final destX = x1.floor();
    final destY = y1.floor();

    final stepX = dx > 0
        ? 1
        : dx < 0
        ? -1
        : 0;
    final stepY = dy > 0
        ? 1
        : dy < 0
        ? -1
        : 0;

    double tMaxX;
    double tMaxY;
    double tDeltaX;
    double tDeltaY;

    if (stepX != 0) {
      final nextBoundaryX = stepX > 0 ? cellX + 1.0 : cellX.toDouble();
      tMaxX = (nextBoundaryX - x0) / dx;
      tDeltaX = 1.0 / dx.abs();
    } else {
      tMaxX = double.infinity;
      tDeltaX = double.infinity;
    }

    if (stepY != 0) {
      final nextBoundaryY = stepY > 0 ? cellY + 1.0 : cellY.toDouble();
      tMaxY = (nextBoundaryY - y0) / dy;
      tDeltaY = 1.0 / dy.abs();
    } else {
      tMaxY = double.infinity;
      tDeltaY = double.infinity;
    }

    _PathCollision? checkCell(int x, int y) {
      if (!world.isInsideIndex(x, y)) {
        return null;
      }
      final cellType = world.cellTypeAt(x, y);
      // Food is also solid - ants must stop at food to pick it up
      if (cellType == CellType.dirt ||
          cellType == CellType.rock ||
          cellType == CellType.food) {
        return _PathCollision(cellX: x, cellY: y, cellType: cellType);
      }
      return null;
    }

    while (cellX != destX || cellY != destY) {
      if (tMaxX < tMaxY) {
        cellX += stepX;
        tMaxX += tDeltaX;
      } else if (tMaxY < tMaxX) {
        cellY += stepY;
        tMaxY += tDeltaY;
      } else {
        cellX += stepX;
        cellY += stepY;
        tMaxX += tDeltaX;
        tMaxY += tDeltaY;
      }
      final collision = checkCell(cellX, cellY);
      if (collision != null) {
        return collision;
      }
    }

    final destinationCollision = checkCell(destX, destY);
    if (destinationCollision != null) {
      return destinationCollision;
    }

    return null;
  }

  double _normalizeAngle(double value) {
    var normalized = value;
    while (normalized > math.pi) {
      normalized -= math.pi * 2;
    }
    while (normalized < -math.pi) {
      normalized += math.pi * 2;
    }
    return normalized;
  }

  void _rotateAway(
    math.Random rng, {
    double minTurn = 0.4,
    double maxTurn = 1.2,
  }) {
    final direction = rng.nextBool() ? 1.0 : -1.0;
    final delta = minTurn + rng.nextDouble() * (maxTurn - minTurn);
    angle = _normalizeAngle(angle + direction * delta);
  }

  void _handleRockCollision(math.Random rng) {
    // Progressive rotation strategy based on consecutive hits
    if (_consecutiveRockHits == 1) {
      // First hit: try 90° turn with some variance
      angle += (math.pi / 2) + (rng.nextDouble() - 0.5) * (math.pi / 3);
    } else if (_consecutiveRockHits == 2) {
      // Second hit: try 135° turn
      angle += (math.pi * 3 / 4) + (rng.nextDouble() - 0.5) * (math.pi / 3);
    } else {
      // Third+ hit: random direction to escape
      angle = rng.nextDouble() * math.pi * 2;
    }
  }

  void _dig(WorldGrid world, int gx, int gy, SimulationConfig config) {
    final applyEnergyCost = config.restEnabled && !_needsRest;
    final spend = applyEnergyCost
        ? math.min(config.digEnergyCost, energy)
        : config.digEnergyCost;
    final damage = spend * config.digDamagePerEnergy;
    world.damageDirt(gx, gy, damage);
    if (applyEnergyCost) {
      energy -= spend;
      if (energy <= 0) {
        energy = 0;
        // Don't rest here - go home first to rest
        if (!_needsRest) {
          _stateBeforeRest = state;
          _needsRest = true;
          _assignRestLocation(world);
        }
        state = AntState.returnHome;
      }
    }
  }

  void _recoverEnergy(double dt, SimulationConfig config) {
    energy += config.energyRecoveryPerSecond * dt;
    // Ants wake up after reaching 70% energy (micro-nap style, like real ants)
    // Real worker ants take ~250 short naps per day, not long sleep periods
    final wakeThreshold = config.energyCapacity * 0.7;
    if (energy >= wakeThreshold) {
      energy = math.min(energy, config.energyCapacity);
      state =
          _stateBeforeRest ?? (hasFood ? AntState.returnHome : AntState.forage);
      _stateBeforeRest = null;
      _needsRest = false;
      _restingSpot = null;
    }
  }

  void _assignRestLocation(WorldGrid world) {
    if (caste == AntCaste.worker ||
        caste == AntCaste.soldier ||
        caste == AntCaste.builder) {
      final Room? preferredBarracks = _selectBarracksRoom(world);
      if (preferredBarracks != null) {
        _restingSpot = preferredBarracks.center.clone();
        return;
      }
    }
    _restingSpot = world.getNestPosition(colonyId).clone();
  }

  Room? _selectBarracksRoom(WorldGrid world) {
    final primary = world.getBarracksRoom(colonyId);
    if (primary != null && !primary.isOverCapacity) {
      return primary;
    }
    for (final room in world.getAllBarracks(colonyId)) {
      if (!room.isOverCapacity) {
        return room;
      }
    }
    return primary;
  }

  void _enterRest() {
    if (state != AntState.rest) {
      _stateBeforeRest = state;
    }
    state = AntState.rest;
    _needsRest = false;
    _restingSpot = null;
  }

  void exitRestState() {
    _wakeFromRest();
  }

  /// Pick up food (from combat kill or food cell)
  void pickUpFood() {
    _carryingFood = true;
    state = AntState.returnHome;
  }

  void _wakeFromRest() {
    if (state == AntState.rest) {
      state =
          _stateBeforeRest ?? (hasFood ? AntState.returnHome : AntState.forage);
      _stateBeforeRest = null;
    }
  }

  // Caste-specific behaviors

  /// Egg behavior: immobile, develop until hatching
  bool _updateEgg(double dt) {
    _growthProgress += dt;
    // Eggs don't move, just develop
    // Colony simulation handles the actual hatching via isReadyToHatch
    return false;
  }

  /// Larva behavior: wiggle slightly while growing
  bool _updateLarva(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
  ) {
    _growthProgress += dt;

    // Larvae wiggle slightly - random small movements
    final wiggleChance = rng.nextDouble();
    if (wiggleChance < 0.3) {
      // 30% chance to wiggle each frame
      // Random turn
      angle += (rng.nextDouble() - 0.5) * 2.0; // Random direction change

      // Very slow movement
      final speed = config.antSpeed * 0.05 * dt;
      final newX = position.x + math.cos(angle) * speed;
      final newY = position.y + math.sin(angle) * speed;

      // Only move if the target is walkable
      if (world.isWalkable(newX, newY)) {
        position.x = newX;
        position.y = newY;
      }
    }

    // Colony simulation handles the actual maturation
    return false;
  }

  /// Queen behavior: stay in chamber, lay eggs periodically
  bool _updateQueen(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
  ) {
    _eggLayTimer += dt;

    final myNest = world.getNestPosition(colonyId);
    final distToNest = position.distanceTo(myNest);
    final wanderRadius =
        config.nestRadius * 0.4; // Stay within inner 40% of nest

    // Check if we're in the queen chamber
    final currentZone = world.zoneAtPosition(position);
    if (currentZone != NestZone.queenChamber) {
      final target = world.nearestZoneCell(position, NestZone.queenChamber, 50);
      if (target != null) {
        final toTarget = target - position;
        final desired = math.atan2(toTarget.y, toTarget.x);
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.15, 0.15);
        final speed = (config.antSpeed * 0.12 + rng.nextDouble() * 0.02) * dt;
        position.x += math.cos(angle) * speed;
        position.y += math.sin(angle) * speed;
      }
    } else {
      angle += (rng.nextDouble() - 0.5) * 0.15;

      if (distToNest > wanderRadius) {
        final toCenter = math.atan2(
          myNest.y - position.y,
          myNest.x - position.x,
        );
        final delta = _normalizeAngle(toCenter - angle);
        angle += delta * 0.05;
      }

      final wiggle = Vector2(
        (rng.nextDouble() - 0.5) * 0.2,
        (rng.nextDouble() - 0.5) * 0.2,
      );
      final nextX = position.x + wiggle.x;
      final nextY = position.y + wiggle.y;

      final dx = nextX - myNest.x;
      final dy = nextY - myNest.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > wanderRadius) {
        position
          ..x = myNest.x + dx / dist * wanderRadius * 0.95
          ..y = myNest.y + dy / dist * wanderRadius * 0.95;
      } else if (world.isWalkable(nextX, nextY)) {
        position
          ..x = nextX
          ..y = nextY;
      }
    }

    // Return true if queen wants to lay an egg (colony handles spawning)
    if (_eggLayTimer >= _eggLayInterval) {
      _eggLayTimer = 0;
      return true; // Signal to colony to spawn a larva
    }
    return false;
  }

  /// Princess behavior: stay in nest area, wander slowly, wait for succession
  bool _updatePrincess(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
  ) {
    final myNest = world.getNestPosition(colonyId);
    final distToNest = position.distanceTo(myNest);
    final wanderRadius =
        config.nestRadius *
        0.6; // Stay within inner 60% of nest (larger than queen)

    // Check if we're in the queen chamber or general nest area
    final currentZone = world.zoneAtPosition(position);
    if (currentZone != NestZone.queenChamber &&
        currentZone != NestZone.general) {
      // Move toward queen chamber
      final target = world.nearestZoneCell(position, NestZone.queenChamber, 50);
      if (target != null) {
        final desired = math.atan2(
          target.y - position.y,
          target.x - position.x,
        );
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.2, 0.2);
        // Princess moves slowly but faster than queen
        final speed = config.antSpeed * 0.2 * dt;
        position.x += math.cos(angle) * speed;
        position.y += math.sin(angle) * speed;
      }
    } else {
      // In nest area - slowly wander around
      angle += (rng.nextDouble() - 0.5) * 0.3;

      // If too far from nest center, bias back toward it
      if (distToNest > wanderRadius) {
        final toCenter = math.atan2(
          myNest.y - position.y,
          myNest.x - position.x,
        );
        final delta = _normalizeAngle(toCenter - angle);
        angle += delta * 0.1;
      }

      // Slow wandering movement (faster than queen but still slow)
      final speed = config.antSpeed * 0.08 * dt;
      final nextX = position.x + math.cos(angle) * speed;
      final nextY = position.y + math.sin(angle) * speed;

      final gx = nextX.floor();
      final gy = nextY.floor();
      if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
        position.x = nextX;
        position.y = nextY;
      } else {
        angle += math.pi * 0.5 + (rng.nextDouble() - 0.5) * 0.5;
      }
    }

    return false; // Princess doesn't lay eggs
  }

  /// Promote this princess to queen (called by colony when queen dies)
  void promoteToQueen() {
    caste = AntCaste.queen;
    _eggLayTimer = 0;
    // Update stats to queen stats
    maxHp = CasteStats.stats[AntCaste.queen]!.baseHp;
    hp = maxHp; // Full heal on promotion
    attack = CasteStats.stats[AntCaste.queen]!.baseAttack;
    defense = CasteStats.stats[AntCaste.queen]!.baseDefense;
    aggression = CasteStats.stats[AntCaste.queen]!.baseAggression;
  }

  /// Nurse behavior: move eggs from home to nursery, patrol nursery area
  /// Returns true if nurse wants to pick up an egg in home room
  bool _updateNurse(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
  ) {
    // Handle resting
    if (state == AntState.rest) {
      _recoverEnergy(dt, config);
      return false;
    }

    // Energy decay
    if (config.restEnabled) {
      energy -= config.energyDecayPerSecond * dt;
      if (energy <= 0) {
        _needsRest = true;
        state = AntState.rest;
        energy = config.digEnergyCost;
        return false;
      }
    }

    final homeRoom = world.getHomeRoom(colonyId);
    final nurseryRoom = world.getNurseryRoom(colonyId);

    // If carrying an egg, navigate to nursery
    if (isCarryingEgg) {
      if (nurseryRoom != null) {
        // Check if we're in the nursery
        if (nurseryRoom.contains(position)) {
          // Signal to drop egg (simulation will handle it)
          return true; // true = ready to drop egg in nursery
        }
        // Navigate toward nursery center
        final desired = math.atan2(
          nurseryRoom.center.y - position.y,
          nurseryRoom.center.x - position.x,
        );
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.4, 0.4);
      }
    } else {
      // Not carrying - check if we should look for eggs in home room
      if (homeRoom != null && homeRoom.contains(position)) {
        // In home room, signal we want to pick up an egg
        return true; // true = want to pick up egg
      }

      // If in nursery, patrol
      if (nurseryRoom != null && nurseryRoom.contains(position)) {
        angle += (rng.nextDouble() - 0.5) * 0.3;
      } else {
        // Navigate toward home room to find eggs, or nursery if no eggs
        final targetRoom = homeRoom ?? nurseryRoom;
        if (targetRoom != null) {
          final desired = math.atan2(
            targetRoom.center.y - position.y,
            targetRoom.center.x - position.x,
          );
          final delta = _normalizeAngle(desired - angle);
          angle += delta.clamp(-0.3, 0.3);
        }
      }
    }

    // Move at reduced speed (nurses are slower)
    final speed = antSpeed * casteSpeedMultiplier * dt * 0.6;
    final vx = math.cos(angle) * speed;
    final vy = math.sin(angle) * speed;
    final nextX = position.x + vx;
    final nextY = position.y + vy;

    // Check bounds and walkability
    final gx = nextX.floor();
    final gy = nextY.floor();
    if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
      position.setValues(nextX, nextY);
    } else {
      _rotateAway(rng, minTurn: 0.4, maxTurn: 0.9);
    }

    return false;
  }

  /// Soldier behavior: patrol nest perimeter, engage enemies
  bool _updateSoldier(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
    Vector2? attackTarget,
  ) {
    // Set defense mode flag for combat system
    _isDefending = attackTarget != null;

    // Handle resting
    if (state == AntState.rest) {
      _recoverEnergy(dt, config);
      return false;
    }

    // Energy decay
    if (config.restEnabled) {
      energy -= config.energyDecayPerSecond * dt;
      if (energy <= 0) {
        _needsRest = true;
        state = AntState.returnHome;
        energy = config.digEnergyCost;
        _assignRestLocation(world);
      }
    }

    final myNest = world.getNestPosition(colonyId);

    if (_needsRest) {
      // Return to nest to rest
      final dir = world.directionToNest(position, colonyId: colonyId);
      if (dir != null && dir.length2 > 0.0001) {
        final desired = math.atan2(dir.y, dir.x);
        final delta = _normalizeAngle(desired - angle);
        // More decisive turning toward nest
        angle += delta.clamp(-0.5, 0.5) * 0.8;
      } else {
        // Fallback for colony 1 or when no path found
        final nestDir = myNest - position;
        if (nestDir.length2 > 0) {
          final desired = math.atan2(nestDir.y, nestDir.x);
          final delta = _normalizeAngle(desired - angle);
          angle += delta.clamp(-0.5, 0.5) * 0.8;
        }
      }

      // Check if at nest
      final distNest = position.distanceTo(myNest);
      if (distNest < config.nestRadius + 0.5) {
        state = AntState.rest;
        _needsRest = false;
        return false;
      }
    } else if (attackTarget != null) {
      // DEFENSE MODE: Colony is under attack - intercept the threat!
      final toTarget = attackTarget - position;
      final distToTarget = toTarget.length;

      if (distToTarget > 1.0) {
        // Move aggressively toward threat position
        final desired = math.atan2(toTarget.y, toTarget.x);
        final delta = _normalizeAngle(desired - angle);
        // Fast, aggressive turning toward threat (0.6 turn rate)
        angle += delta.clamp(-0.6, 0.6);
      } else {
        // At threat location - hold position and look around
        angle += (rng.nextDouble() - 0.5) * 0.5;
      }

      // Don't stray too far from nest even when defending
      final distNest = position.distanceTo(myNest);
      final maxDefenseRange = config.nestRadius * 4.0;
      if (distNest > maxDefenseRange) {
        // Pull back toward nest slightly
        final inward = math.atan2(myNest.y - position.y, myNest.x - position.x);
        final delta = _normalizeAngle(inward - angle);
        angle += delta.clamp(-0.3, 0.3);
      }
    } else {
      // Normal patrol behavior: stay near nest outer area
      final currentZone = world.zoneAtPosition(position);
      final distNest = position.distanceTo(myNest);

      // Patrol radius - stay in general nest area or just outside
      final patrolInner = config.nestRadius * 0.5;
      final patrolOuter = config.nestRadius * 2.0;

      if (distNest < patrolInner) {
        // Too close to center - move outward
        final outward = math.atan2(
          position.y - myNest.y,
          position.x - myNest.x,
        );
        final delta = _normalizeAngle(outward - angle);
        angle += delta.clamp(-0.2, 0.2);
      } else if (distNest > patrolOuter || currentZone == NestZone.none) {
        // Too far or outside nest - return
        final inward = math.atan2(myNest.y - position.y, myNest.x - position.x);
        final delta = _normalizeAngle(inward - angle);
        angle += delta.clamp(-0.2, 0.2);
      } else {
        // In patrol zone - wander with subtle bias
        angle += (rng.nextDouble() - 0.5) * 0.3;
        final toCenter = math.atan2(
          myNest.y - position.y,
          myNest.x - position.x,
        );
        final bias = _normalizeAngle(toCenter - angle);
        angle += bias * 0.05;
      }
    }

    // Move at soldier speed (faster when defending)
    final speedMult = attackTarget != null ? 1.3 : 1.0; // 30% faster in defense
    final speed = antSpeed * casteSpeedMultiplier * speedMult * dt;
    final vx = math.cos(angle) * speed;
    final vy = math.sin(angle) * speed;
    final nextX = position.x + vx;
    final nextY = position.y + vy;

    // Check bounds and walkability
    final gx = nextX.floor();
    final gy = nextY.floor();
    if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
      position.setValues(nextX, nextY);
    } else {
      _rotateAway(rng);
    }

    return false;
  }

  // Builder task state
  BuilderTask _builderTask = BuilderTask.idle;
  Vector2? _builderTarget;
  RoomType? _builderTargetRoomType;
  double _builderTargetRadius = 0;
  final List<(int, int)> _builderPendingCells = <(int, int)>[];
  int _activeBuilderTaskId = -1;
  int? _completedBuilderTaskId;
  bool _builderEmergencyTask = false;
  double _builderTaskTimer = 0;

  bool get isBuilderIdle =>
      caste == AntCaste.builder &&
      _builderTask == BuilderTask.idle &&
      !_needsRest &&
      state != AntState.rest;

  void assignBuilderTask({
    required BuilderTask task,
    required Vector2 target,
    RoomType? roomType,
    double radius = 3.0,
    bool emergency = false,
    int taskId = -1,
    List<(int, int)>? blueprintCells,
  }) {
    if (caste != AntCaste.builder) return;
    _builderTask = task;
    _builderTarget = target.clone();
    _builderTargetRoomType = roomType;
    _builderTargetRadius = radius;
    _builderPendingCells.clear();
    if (blueprintCells != null && blueprintCells.isNotEmpty) {
      _builderPendingCells.addAll(blueprintCells);
    }
    _builderEmergencyTask = emergency;
    _activeBuilderTaskId = taskId;
    _builderTaskTimer = 0;
  }

  void cancelBuilderTask() {
    if (caste != AntCaste.builder) return;
    _builderTask = BuilderTask.idle;
    _builderTarget = null;
    _builderPendingCells.clear();
    _builderTargetRoomType = null;
    _builderTargetRadius = 0;
    _activeBuilderTaskId = -1;
    _builderEmergencyTask = false;
    _builderTaskTimer = 0;
  }

  int? takeCompletedBuilderTaskId() {
    final id = _completedBuilderTaskId;
    _completedBuilderTaskId = null;
    return id;
  }

  /// Update builder behavior - constructs rooms and reinforces walls
  bool _updateBuilder(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
  ) {
    if (config.restEnabled && state == AntState.rest) {
      _recoverEnergy(dt, config);
      return false;
    }

    if (config.restEnabled) {
      energy -= config.energyDecayPerSecond * dt;
      if (energy <= config.energyCapacity * 0.15) {
        if (!_needsRest) {
          _stateBeforeRest = state;
          _needsRest = true;
          _assignRestLocation(world);
        }
        state = AntState.returnHome;
        _builderTask = BuilderTask.returningHome;
      }
    } else {
      energy = config.energyCapacity;
    }

    if (_needsRest) {
      final target = _restingSpot ?? world.getNestPosition(colonyId);
      _moveTowardsBuilderTarget(
        target,
        dt,
        world,
        rng,
        antSpeed,
        stopDistance: config.nestRadius * 0.4,
      );
      return false;
    }

    if (_builderTask == BuilderTask.returningHome) {
      final reached = _moveTowardsBuilderTarget(
        world.getNestPosition(colonyId),
        dt,
        world,
        rng,
        antSpeed,
        stopDistance: config.nestRadius * 0.4,
      );
      if (reached) {
        _builderTask = BuilderTask.idle;
      }
      return false;
    }

    if (_builderTask == BuilderTask.idle) {
      final reinforced = _reinforceNearbyCells(world, config);
      if (!reinforced) {
        _patrolBuilderNearNest(world, rng, dt, antSpeed, config);
      }
      return false;
    }

    if (_builderTask != BuilderTask.idle) {
      _builderTaskTimer += dt;
      if (_builderTaskTimer > 120) {
        cancelBuilderTask();
        return false;
      }
    }

    final target = _builderTarget;
    if (target == null) {
      cancelBuilderTask();
      return false;
    }

    final arrived = _moveTowardsBuilderTarget(
      target,
      dt,
      world,
      rng,
      antSpeed,
      stopDistance: _builderTargetRadius + 0.8,
    );

    if (!arrived) {
      return false;
    }

    final finished = _performBuilderWork(world, config, rng);
    if (finished) {
      _finishBuilderTask();
      return true;
    }
    return false;
  }

  void _finishBuilderTask() {
    final completedId = _activeBuilderTaskId;
    cancelBuilderTask();
    if (completedId >= 0) {
      _completedBuilderTaskId = completedId;
    }
  }

  bool _moveTowardsBuilderTarget(
    Vector2 target,
    double dt,
    WorldGrid world,
    math.Random rng,
    double antSpeed, {
    double stopDistance = 0.5,
  }) {
    final toTarget = target - position;
    final distance = toTarget.length;
    if (distance <= stopDistance) {
      return true;
    }
    final desired = math.atan2(toTarget.y, toTarget.x);
    final delta = _normalizeAngle(desired - angle);
    angle += delta.clamp(-0.4, 0.4);

    final speedFactor = _builderEmergencyTask ? 0.9 : 0.6;
    final moveDistance = antSpeed * casteSpeedMultiplier * speedFactor * dt;
    final nextX = position.x + math.cos(angle) * moveDistance;
    final nextY = position.y + math.sin(angle) * moveDistance;
    final gx = nextX.floor();
    final gy = nextY.floor();
    if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
      position.setValues(nextX, nextY);
    } else {
      _rotateAway(rng, minTurn: 0.5, maxTurn: 1.0);
    }
    return false;
  }

  bool _performBuilderWork(
    WorldGrid world,
    SimulationConfig config,
    math.Random rng,
  ) {
    if (_builderPendingCells.isEmpty) {
      switch (_builderTask) {
        case BuilderTask.buildingRoom:
          _builderPendingCells.addAll(_generateRoomCells(world, rng));
          break;
        case BuilderTask.reinforcingWall:
          _builderPendingCells.addAll(_generatePerimeterCells(world, rng));
          break;
        case BuilderTask.emergencyDefense:
          _builderPendingCells.addAll(_generateDefenseCells(world));
          break;
        case BuilderTask.constructingBlueprint:
          break; // Cells were pre-seeded by the colony
        default:
          break;
      }
    }

    if (_builderPendingCells.isEmpty) {
      return true;
    }

    final maxSteps = caste == AntCaste.builder
        ? 4 * _builderDigStepMultiplier
        : 4;
    var steps = 0;
    while (_builderPendingCells.isNotEmpty && steps < maxSteps) {
      final cell = _builderPendingCells.removeLast();
      final x = cell.$1;
      final y = cell.$2;
      if (!world.isInsideIndex(x, y)) {
        steps++;
        continue;
      }

      switch (_builderTask) {
        case BuilderTask.buildingRoom:
        case BuilderTask.constructingBlueprint:
          if (world.cellTypeAt(x, y) != CellType.rock) {
            world.setCell(x, y, CellType.air);
            if (config.restEnabled) {
              energy = math.max(0, energy - config.digEnergyCost * 0.25);
            }
          }
          break;
        case BuilderTask.reinforcingWall:
        case BuilderTask.emergencyDefense:
          if (world.reinforceCell(x, y) && config.restEnabled) {
            energy = math.max(0, energy - config.digEnergyCost * 0.15);
          }
          break;
        default:
          break;
      }

      steps++;

      if (config.restEnabled && energy <= 0) {
        if (!_needsRest) {
          _stateBeforeRest = state;
          _needsRest = true;
          _assignRestLocation(world);
        }
        state = AntState.returnHome;
        return false;
      }
    }

    return _builderPendingCells.isEmpty;
  }

  List<(int, int)> _generateRoomCells(WorldGrid world, math.Random rng) {
    final target = _builderTarget;
    if (target == null) {
      return <(int, int)>[];
    }
    final cx = target.x.floor();
    final cy = target.y.floor();
    final radius = _builderTargetRadius.ceil() + 1;
    final cells = <(int, int)>[];
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!world.isInsideIndex(x, y)) continue;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= _builderTargetRadius &&
            world.cellTypeAt(x, y) != CellType.air) {
          cells.add((x, y));
        }
      }
    }
    cells.shuffle(rng);
    return cells;
  }

  List<(int, int)> _generatePerimeterCells(WorldGrid world, math.Random rng) {
    final target = _builderTarget;
    if (target == null) {
      return <(int, int)>[];
    }
    Room? room = world.getRoomAt(target);
    if (room == null && _builderTargetRoomType != null) {
      for (final candidate in world.getRoomsOfType(
        _builderTargetRoomType!,
        colonyId,
      )) {
        if (candidate.center.distanceTo(target) <=
            candidate.radius + _builderTargetRadius + 1) {
          room = candidate;
          break;
        }
      }
    }
    if (room == null) {
      return <(int, int)>[];
    }
    final perimeter = world.getRoomPerimeter(room);
    perimeter.shuffle(rng);
    return perimeter;
  }

  List<(int, int)> _generateDefenseCells(WorldGrid world) {
    final target = _builderTarget;
    if (target == null) {
      return <(int, int)>[];
    }
    final origin = world.getNestPosition(colonyId);
    final cells = <(int, int)>[];
    final steps = math.max(4, (origin.distanceTo(target) * 1.2).floor());
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (origin.x + (target.x - origin.x) * t).floor();
      final y = (origin.y + (target.y - origin.y) * t).floor();
      if (!world.isInsideIndex(x, y)) continue;
      cells.add((x, y));
    }
    return cells;
  }

  bool _reinforceNearbyCells(WorldGrid world, SimulationConfig config) {
    final gx = position.x.floor();
    final gy = position.y.floor();
    for (var dx = -2; dx <= 2; dx++) {
      for (var dy = -2; dy <= 2; dy++) {
        final nx = gx + dx;
        final ny = gy + dy;
        if (!world.isInsideIndex(nx, ny)) continue;
        final room = world.getRoomAt(Vector2(nx + 0.5, ny + 0.5));
        if (room == null || room.colonyId != colonyId) continue;
        if (world.reinforceCell(nx, ny)) {
          if (config.restEnabled) {
            energy = math.max(0, energy - config.digEnergyCost * 0.1);
          }
          return true;
        }
      }
    }
    return false;
  }

  void _patrolBuilderNearNest(
    WorldGrid world,
    math.Random rng,
    double dt,
    double antSpeed,
    SimulationConfig config,
  ) {
    final nestPos = world.getNestPosition(colonyId);
    final distToNest = position.distanceTo(nestPos);
    final maxRange = config.nestRadius * 3.0;
    if (distToNest > maxRange) {
      final desired = math.atan2(
        nestPos.y - position.y,
        nestPos.x - position.x,
      );
      final delta = _normalizeAngle(desired - angle);
      angle += delta.clamp(-0.3, 0.3);
    } else {
      angle += (rng.nextDouble() - 0.5) * 0.2;
    }

    final speed = antSpeed * casteSpeedMultiplier * 0.5 * dt;
    final nextX = position.x + math.cos(angle) * speed;
    final nextY = position.y + math.sin(angle) * speed;
    final gx = nextX.floor();
    final gy = nextY.floor();
    if (world.isInsideIndex(gx, gy) && world.isWalkableCell(gx, gy)) {
      position.setValues(nextX, nextY);
    }
  }

  /// Nurse methods for carrying larvae
  void pickUpLarva(int larvaId) {
    _carryingLarvaId = larvaId;
  }

  void dropLarva() {
    _carryingLarvaId = -1;
  }

  /// Nurse methods for carrying eggs
  void pickUpEgg(int eggId) {
    _carryingEggId = eggId;
  }

  void dropEgg() {
    _carryingEggId = -1;
  }

  /// Reset egg timer (called after spawning larva)
  void resetEggTimer() {
    _eggLayTimer = 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': position.x,
      'y': position.y,
      'angle': angle,
      'state': state.index,
      'carryingFood': _carryingFood,
      'energy': energy,
      'stateBeforeRest': _stateBeforeRest?.index,
      'explorerTendency': _explorerTendency,
      'caste': caste.index,
      'colonyId': colonyId,
      'aggression': aggression,
      'attack': attack,
      'defense': defense,
      'maxHp': maxHp,
      'hp': hp,
      'growthProgress': _growthProgress,
      'carryingLarvaId': _carryingLarvaId,
      'carryingEggId': _carryingEggId,
      'eggLayTimer': _eggLayTimer,
      'age': _age,
      'builderTask': _builderTask.index,
      'builderTargetX': _builderTarget?.x,
      'builderTargetY': _builderTarget?.y,
      'builderTargetRadius': _builderTargetRadius,
      'builderTaskId': _activeBuilderTaskId,
      'builderEmergency': _builderEmergencyTask,
    };
  }

  static Ant fromJson(Map<String, dynamic> json) {
    final stateIndex = (json['state'] as num?)?.toInt() ?? 0;
    final restIndex = (json['stateBeforeRest'] as num?)?.toInt();
    final clampedState = _clampStateIndex(stateIndex)!;
    final clampedRest = _clampStateIndex(restIndex);
    final casteIndex = (json['caste'] as num?)?.toInt() ?? 0;
    final clampedCaste = casteIndex.clamp(0, AntCaste.values.length - 1);
    final builderTaskIndex = (json['builderTask'] as num?)?.toInt() ?? 0;
    final builderTaskIndexClamped = builderTaskIndex
        .clamp(0, BuilderTask.values.length - 1)
        .toInt();
    final builderTask = BuilderTask.values[builderTaskIndexClamped];
    Vector2? builderTarget;
    final builderTargetX = (json['builderTargetX'] as num?)?.toDouble();
    final builderTargetY = (json['builderTargetY'] as num?)?.toDouble();
    if (builderTargetX != null && builderTargetY != null) {
      builderTarget = Vector2(builderTargetX, builderTargetY);
    }
    return Ant.rehydrated(
      id: (json['id'] as num?)?.toInt() ?? _nextId++,
      position: Vector2(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      angle: (json['angle'] as num).toDouble(),
      state: AntState.values[clampedState],
      carryingFood: json['carryingFood'] as bool? ?? false,
      energy: (json['energy'] as num?)?.toDouble() ?? 0,
      stateBeforeRest: clampedRest == null
          ? null
          : AntState.values[clampedRest],
      explorerTendency:
          (json['explorerTendency'] as num?)?.toDouble() ??
          (json['isExplorer'] == true ? 0.2 : 0.05), // Migrate old saves
      caste: AntCaste.values[clampedCaste],
      colonyId:
          (json['colonyId'] as num?)?.toInt() ??
          (json['isEnemy'] == true ? 1 : 0), // Migrate old saves
      aggression:
          (json['aggression'] as num?)?.toDouble() ??
          CasteStats.stats[AntCaste.values[clampedCaste]]!.baseAggression,
      attack: (json['attack'] as num?)?.toDouble() ?? 5,
      defense: (json['defense'] as num?)?.toDouble() ?? 2,
      maxHpValue: (json['maxHp'] as num?)?.toDouble() ?? 100,
      hp: (json['hp'] as num?)?.toDouble(),
      growthProgress: (json['growthProgress'] as num?)?.toDouble() ?? 0.0,
      carryingLarvaId: (json['carryingLarvaId'] as num?)?.toInt() ?? -1,
      carryingEggId: (json['carryingEggId'] as num?)?.toInt() ?? -1,
      eggLayTimer: (json['eggLayTimer'] as num?)?.toDouble() ?? 0.0,
      age: (json['age'] as num?)?.toDouble() ?? 0.0,
      builderTask: builderTask,
      builderTarget: builderTarget,
      builderTargetRadius:
          (json['builderTargetRadius'] as num?)?.toDouble() ?? 0.0,
      activeBuilderTaskId: (json['builderTaskId'] as num?)?.toInt() ?? -1,
      builderEmergencyTask: json['builderEmergency'] as bool? ?? false,
    );
  }
}

int? _clampStateIndex(num? value) {
  if (value == null) {
    return null;
  }
  final minIndex = 0;
  final maxIndex = AntState.values.length - 1;
  final clamped = value.clamp(minIndex, maxIndex).toInt();
  if (clamped < minIndex) {
    return minIndex;
  }
  if (clamped > maxIndex) {
    return maxIndex;
  }
  return clamped;
}

class _PathCollision {
  final int cellX;
  final int cellY;
  final CellType cellType;

  _PathCollision({
    required this.cellX,
    required this.cellY,
    required this.cellType,
  });
}
