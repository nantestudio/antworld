import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

enum AntState { forage, returnHome, rest }

/// Ant castes with different roles and abilities
enum AntCaste {
  worker,   // Basic forager/digger
  soldier,  // Combat-focused, patrols and defends
  nurse,    // Stays in nest, cares for larvae
  drone,    // Male, reproductive only
  queen,    // Produces eggs, stays in nest center
  larva,    // Immobile, needs feeding to mature
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
  });

  final double speedMultiplier;
  final double baseHp;
  final double baseAttack;
  final double baseDefense;
  final bool canForage;
  final (double, double) explorerRange; // min, max explorer tendency

  static const Map<AntCaste, CasteStats> stats = {
    AntCaste.worker: CasteStats(
      speedMultiplier: 1.0,
      baseHp: 100,
      baseAttack: 5,
      baseDefense: 2,
      canForage: true,
      explorerRange: (0.0, 0.3),
    ),
    AntCaste.soldier: CasteStats(
      speedMultiplier: 0.8,
      baseHp: 150,
      baseAttack: 15,
      baseDefense: 8,
      canForage: false,
      explorerRange: (0.1, 0.2),
    ),
    AntCaste.nurse: CasteStats(
      speedMultiplier: 0.7,
      baseHp: 80,
      baseAttack: 2,
      baseDefense: 1,
      canForage: false,
      explorerRange: (0.0, 0.05),
    ),
    AntCaste.drone: CasteStats(
      speedMultiplier: 1.1,
      baseHp: 60,
      baseAttack: 1,
      baseDefense: 1,
      canForage: false,
      explorerRange: (0.0, 0.1),
    ),
    AntCaste.queen: CasteStats(
      speedMultiplier: 0.3,
      baseHp: 500,
      baseAttack: 3,
      baseDefense: 10,
      canForage: false,
      explorerRange: (0.0, 0.0),
    ),
    AntCaste.larva: CasteStats(
      speedMultiplier: 0.0,
      baseHp: 50,
      baseAttack: 0,
      baseDefense: 0,
      canForage: false,
      explorerRange: (0.0, 0.0),
    ),
  };
}

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
    this.isEnemy = false,
  })  : id = _nextId++,
        position = startPosition.clone(),
        _explorerTendency = _generateExplorerTendency(caste, rng, isEnemy),
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
    this.isEnemy = false,
    required this.attack,
    required this.defense,
    required double maxHpValue,
    double? hp,
    double growthProgress = 0.0,
    int carryingLarvaId = -1,
    double eggLayTimer = 0.0,
  })  : position = position.clone(),
        _carryingFood = carryingFood,
        _stateBeforeRest = stateBeforeRest,
        _explorerTendency = explorerTendency,
        maxHp = maxHpValue,
        hp = (hp ?? maxHpValue).clamp(0, maxHpValue),
        _growthProgress = growthProgress,
        _carryingLarvaId = carryingLarvaId,
        _eggLayTimer = eggLayTimer;

  static double _generateExplorerTendency(AntCaste caste, math.Random rng, bool isEnemy) {
    if (isEnemy) return 0.1; // Enemies have low explorer tendency
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
  final AntCaste caste;
  final bool isEnemy;
  final double attack;
  final double defense;
  final double maxHp;
  double hp;
  bool _needsRest = false;

  // Larva growth (only used when caste == larva)
  double _growthProgress = 0.0;
  static const double _growthTimeToMature = 60.0; // seconds to mature

  // Nurse carrying larva (reference by ID, -1 = not carrying)
  int _carryingLarvaId = -1;

  // Queen egg laying timer
  double _eggLayTimer = 0.0;
  static const double _eggLayInterval = 30.0; // seconds between laying eggs

  // Stuck detection
  final Vector2 _lastPosition = Vector2.zero();
  double _stuckTime = 0;
  static const double _stuckThreshold = 30.0; // seconds before considered stuck
  static const double _moveThreshold = 0.5; // minimum distance to count as moved

  bool get hasFood => _carryingFood;
  bool get isDead => hp <= 0;
  bool get isStuck => _stuckTime >= _stuckThreshold;
  double get stuckTime => _stuckTime;
  double get explorerTendency => _explorerTendency;
  bool get isExplorer => _explorerTendency > 0.15; // High tendency = explorer
  bool get needsRest => _needsRest;
  AntState? get stateBeforeRest => _stateBeforeRest;
  double get casteSpeedMultiplier => CasteStats.stats[caste]!.speedMultiplier;
  bool get canForage => CasteStats.stats[caste]!.canForage;
  double get growthProgress => _growthProgress;
  bool get isCarryingLarva => _carryingLarvaId >= 0;
  int get carryingLarvaId => _carryingLarvaId;
  bool get isReadyToMature => caste == AntCaste.larva && _growthProgress >= _growthTimeToMature;
  bool get wantsToLayEgg => caste == AntCaste.queen && _eggLayTimer >= _eggLayInterval;

  void applyDamage(double amount) {
    hp = math.max(0, hp - amount);
  }

  bool update(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
    {Vector2? attackTarget}
  ) {
    if (dt == 0) return false;

    // Stuck detection - track if ant has moved (skip for resting ants)
    if (state != AntState.rest) {
      final distMoved = position.distanceTo(_lastPosition);
      if (distMoved < _moveThreshold) {
        _stuckTime += dt;
      } else {
        _stuckTime = 0;
        _lastPosition.setFrom(position);
      }
    } else {
      _stuckTime = 0; // Reset when resting
    }

    if (isEnemy) {
      _updateHostile(dt, config, world, rng, antSpeed, attackTarget);
      return false;
    }

    // Caste-specific behaviors
    switch (caste) {
      case AntCaste.larva:
        return _updateLarva(dt);
      case AntCaste.queen:
        return _updateQueen(dt, config, world, rng);
      case AntCaste.nurse:
        // Nurses use modified worker behavior (handled below with zone awareness)
        break;
      case AntCaste.soldier:
        // Soldiers patrol and don't forage (handled below)
        break;
      case AntCaste.worker:
      case AntCaste.drone:
        // Workers and drones use standard foraging behavior
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

      if (hitBlock == CellType.dirt) {
        _dig(world, hitX, hitY, config);
        angle += math.pi / 2 + (rng.nextDouble() - 0.5) * 0.6;
        _consecutiveRockHits = 0; // Reset rock hit counter on dirt collision
      } else if (hitBlock == CellType.rock) {
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
      }
      return false;
    }

    // Check if destination is out of bounds
    final gx = nextX.floor();
    final gy = nextY.floor();
    if (!world.isInsideIndex(gx, gy)) {
      angle += math.pi;
      return false;
    }

    position.setValues(nextX, nextY);

    // Successfully moved - reset collision tracking
    if (_collisionCooldown > 0) {
      _collisionCooldown--;
    }
    if (_consecutiveRockHits > 0) {
      _consecutiveRockHits = 0; // Reset when moving freely
    }

    final depositX = position.x.floor();
    final depositY = position.y.floor();
    if (!isEnemy && world.isInsideIndex(depositX, depositY)) {
      if (hasFood) {
        // Vary deposit strength ±20% for natural trail variation
        final strength =
            config.foodDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositFoodPheromone(depositX, depositY, strength);
      } else {
        final strength =
            config.homeDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositHomePheromone(depositX, depositY, strength);
      }
    }

    // Check for food at destination
    final destBlock = world.cellTypeAt(gx, gy);
    if (!isEnemy && destBlock == CellType.food && !hasFood) {
      _carryingFood = true;
      state = AntState.returnHome;
      world.removeFood(gx, gy);
      angle += config.foodPickupRotation + (rng.nextDouble() - 0.5) * 0.2;
    }

    final distNest = position.distanceTo(world.nestPosition);
    if (!isEnemy && distNest < config.nestRadius + 0.5) {
      bool deliveredFood = false;
      if (hasFood) {
        _carryingFood = false;
        deliveredFood = true;
        angle += math.pi;
      }
      if (_needsRest) {
        // Turn around if we didn't already (from dropping food)
        if (!deliveredFood) {
          angle += math.pi;
        }
        // Set state to forage before resting so we resume foraging after
        state = AntState.forage;
        _enterRest();
        return deliveredFood;
      }
      if (deliveredFood) {
        state = AntState.forage;
        return true;
      }
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
      double? desiredAngle;
      final dir = world.directionToNest(position);
      if (dir != null && dir.length2 > 0.0001) {
        desiredAngle = math.atan2(dir.y, dir.x);
      } else {
        final nestDir = world.nestPosition - position;
        if (nestDir.length2 > 0) {
          desiredAngle = math.atan2(nestDir.y, nestDir.x);
        }
      }
      if (desiredAngle != null) {
        // Gradually turn toward home instead of snapping
        final delta = _normalizeAngle(desiredAngle - angle);
        // Turn at most 0.3 radians toward the target (slower, more organic)
        // Only apply 50-80% of the turn for smoother curves
        final turnAmount = delta.clamp(-0.3, 0.3) * (0.5 + rng.nextDouble() * 0.3);
        angle += turnAmount;
        // Add stronger wiggle for natural ant-like movement
        angle += (rng.nextDouble() - 0.5) * 0.25;
      }
      return;
    }

    // Random exploration: based on explorer tendency (personality trait)
    // Higher tendency = more likely to ignore pheromones and wander
    final exploreChance = 0.01 + _explorerTendency * 0.5; // 1% to 51% based on tendency
    if (rng.nextDouble() < exploreChance) {
      angle += (rng.nextDouble() - 0.5) * config.randomTurnStrength;
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
      // No food in range - wander more aggressively to explore
      angle += (rng.nextDouble() - 0.5) * 0.4;
    } else if (!steered) {
      // Small random wandering when no guidance at all
      angle += (rng.nextDouble() - 0.5) * 0.15;
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

    final behavior = state == AntState.rest && _stateBeforeRest != null
        ? _stateBeforeRest!
        : state;

    if (behavior == AntState.forage) {
      var value = world.foodPheromoneAt(gx, gy);
      if (world.cellTypeAt(gx, gy) == CellType.food) {
        value += 10;
      }
      // Add perceptual noise: ±15% variation
      value *= (0.85 + rng.nextDouble() * 0.3);
      return value;
    }

    var value = world.homePheromoneAt(gx, gy);
    // Add perceptual noise: ±15% variation
    value *= (0.85 + rng.nextDouble() * 0.3);
    return value;
  }

  Vector2? _biasTowardFood(
    WorldGrid world,
    SimulationConfig config,
    math.Random rng,
  ) {
    final target = world.nearestFood(position, config.foodSenseRange);
    if (target == null) {
      return null;
    }
    final desired = math.atan2(target.y - position.y, target.x - position.x);
    final delta = _normalizeAngle(desired - angle);
    angle += delta.clamp(-0.3, 0.3) * 0.4;
    angle += (rng.nextDouble() - 0.5) * 0.05;
    return target;
  }

  void _updateHostile(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
    Vector2? attackTarget,
  ) {
    final target = attackTarget ?? world.nestPosition;
    final desired = math.atan2(target.y - position.y, target.x - position.x);
    final delta = _normalizeAngle(desired - angle);
    angle += delta.clamp(-0.35, 0.35) * 0.8;
    angle += (rng.nextDouble() - 0.5) * 0.12;

    final distance = antSpeed * dt * 0.95;
    final vx = math.cos(angle) * distance;
    final vy = math.sin(angle) * distance;
    final nextX = position.x + vx;
    final nextY = position.y + vy;

    final collision = _checkPathCollision(
      position.x,
      position.y,
      nextX,
      nextY,
      world,
    );

    if (collision != null) {
      _dig(world, collision.cellX, collision.cellY, config);
      angle += (rng.nextDouble() - 0.5) * math.pi;
      return;
    }

    final gx = nextX.floor();
    final gy = nextY.floor();
    if (!world.isInsideIndex(gx, gy)) {
      angle += math.pi * 0.5;
      return;
    }

    position.setValues(nextX, nextY);
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
      if (cellType == CellType.dirt || cellType == CellType.rock) {
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
    final applyEnergyCost = config.restEnabled && !isEnemy && !_needsRest;
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
    }
  }

  void _enterRest() {
    if (state != AntState.rest) {
      _stateBeforeRest = state;
    }
    state = AntState.rest;
    _needsRest = false;
  }

  void exitRestState() {
    _wakeFromRest();
  }

  void _wakeFromRest() {
    if (state == AntState.rest) {
      state =
          _stateBeforeRest ?? (hasFood ? AntState.returnHome : AntState.forage);
      _stateBeforeRest = null;
    }
  }

  // Caste-specific behaviors

  /// Larva behavior: immobile, just grow over time
  bool _updateLarva(double dt) {
    _growthProgress += dt;
    // Larvae don't move, just signal when ready to mature
    // Colony simulation handles the actual maturation
    return false;
  }

  /// Queen behavior: stay in chamber, lay eggs periodically
  bool _updateQueen(double dt, SimulationConfig config, WorldGrid world, math.Random rng) {
    _eggLayTimer += dt;

    // Check if we're in the queen chamber
    final currentZone = world.zoneAtPosition(position);
    if (currentZone != NestZone.queenChamber) {
      // Move toward queen chamber
      final target = world.nearestZoneCell(position, NestZone.queenChamber, 50);
      if (target != null) {
        final desired = math.atan2(target.y - position.y, target.x - position.x);
        final delta = _normalizeAngle(desired - angle);
        angle += delta.clamp(-0.2, 0.2);
        // Queen moves very slowly
        final speed = config.antSpeed * 0.1 * dt;
        position.x += math.cos(angle) * speed;
        position.y += math.sin(angle) * speed;
      }
    } else {
      // In chamber - just wiggle slightly in place
      angle += (rng.nextDouble() - 0.5) * 0.1;
    }

    // Return true if queen wants to lay an egg (colony handles spawning)
    if (_eggLayTimer >= _eggLayInterval) {
      _eggLayTimer = 0;
      return true; // Signal to colony to spawn a larva
    }
    return false;
  }

  /// Nurse methods for carrying larvae
  void pickUpLarva(int larvaId) {
    _carryingLarvaId = larvaId;
  }

  void dropLarva() {
    _carryingLarvaId = -1;
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
      'isEnemy': isEnemy,
      'attack': attack,
      'defense': defense,
      'maxHp': maxHp,
      'hp': hp,
      'growthProgress': _growthProgress,
      'carryingLarvaId': _carryingLarvaId,
      'eggLayTimer': _eggLayTimer,
    };
  }

  static Ant fromJson(Map<String, dynamic> json) {
    final stateIndex = (json['state'] as num?)?.toInt() ?? 0;
    final restIndex = (json['stateBeforeRest'] as num?)?.toInt();
    final clampedState = _clampStateIndex(stateIndex)!;
    final clampedRest = _clampStateIndex(restIndex);
    final casteIndex = (json['caste'] as num?)?.toInt() ?? 0;
    final clampedCaste = casteIndex.clamp(0, AntCaste.values.length - 1);
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
      explorerTendency: (json['explorerTendency'] as num?)?.toDouble() ??
          (json['isExplorer'] == true ? 0.2 : 0.05), // Migrate old saves
      caste: AntCaste.values[clampedCaste],
      isEnemy: json['isEnemy'] as bool? ?? false,
      attack: (json['attack'] as num?)?.toDouble() ?? 5,
      defense: (json['defense'] as num?)?.toDouble() ?? 2,
      maxHpValue: (json['maxHp'] as num?)?.toDouble() ?? 100,
      hp: (json['hp'] as num?)?.toDouble(),
      growthProgress: (json['growthProgress'] as num?)?.toDouble() ?? 0.0,
      carryingLarvaId: (json['carryingLarvaId'] as num?)?.toInt() ?? -1,
      eggLayTimer: (json['eggLayTimer'] as num?)?.toDouble() ?? 0.0,
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
