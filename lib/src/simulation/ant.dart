import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

enum AntState { forage, returnHome, rest }

class Ant {
  Ant({
    required Vector2 startPosition,
    required this.angle,
    required this.energy,
    required math.Random rng,
    required double explorerRatio,
    required this.attack,
    required this.defense,
    required double maxHpValue,
    this.isEnemy = false,
  })  : position = startPosition.clone(),
        _isExplorer =
            !isEnemy && rng.nextDouble() < explorerRatio,
        maxHp = maxHpValue,
        hp = maxHpValue;

  Ant.rehydrated({
    required Vector2 position,
    required this.angle,
    required this.state,
    required bool carryingFood,
    required this.energy,
    AntState? stateBeforeRest,
    bool isExplorer = false,
    this.isEnemy = false,
    required this.attack,
    required this.defense,
    required double maxHpValue,
    double? hp,
  })  : position = position.clone(),
        _carryingFood = carryingFood,
        _stateBeforeRest = stateBeforeRest,
        _isExplorer = isExplorer,
        maxHp = maxHpValue,
        hp = (hp ?? maxHpValue).clamp(0, maxHpValue);

  final Vector2 position;
  double angle;
  AntState state = AntState.forage;
  AntState? _stateBeforeRest;
  double energy;
  bool _carryingFood = false;
  int _consecutiveRockHits = 0;
  int _collisionCooldown = 0;
  double _speedMultiplier = 1.0;
  final bool _isExplorer; // explorer ants ignore pheromones more often
  final bool isEnemy;
  final double attack;
  final double defense;
  final double maxHp;
  double hp;
  bool _needsRest = false;

  // Stuck detection
  final Vector2 _lastPosition = Vector2.zero();
  double _stuckTime = 0;
  static const double _stuckThreshold = 30.0; // seconds before considered stuck
  static const double _moveThreshold = 0.5; // minimum distance to count as moved

  bool get hasFood => _carryingFood;
  bool get isDead => hp <= 0;
  bool get isStuck => _stuckTime >= _stuckThreshold;
  double get stuckTime => _stuckTime;
  bool get isExplorer => _isExplorer;
  bool get needsRest => _needsRest;
  AntState? get stateBeforeRest => _stateBeforeRest;

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

    // Random exploration: explorers ignore pheromones more often (20% vs 1% chance)
    final exploreChance = _isExplorer ? 0.20 : 0.01;
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
        final mistakeChance = _isExplorer ? 0.15 : 0.03;
        final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
        angle -= (rng.nextDouble() * 0.15 + 0.08) * mistakeFactor;
        steered = true;
      } else {
        // Right is strongest - turn right
        final mistakeChance = _isExplorer ? 0.15 : 0.03;
        final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
        angle += (rng.nextDouble() * 0.15 + 0.08) * mistakeFactor;
        steered = true;
      }
    }

    // Only use direct food sensing when NO pheromones detected and only occasionally
    if (!steered && behavior == AntState.forage) {
      // Only 15% chance per frame to check for direct food (don't override pheromones)
      if (rng.nextDouble() < 0.15) {
        final foodTarget = _biasTowardFood(world, config, rng);
        if (foodTarget != null) {
          // Check if there's dirt ahead in the direction of food
          final nextX = position.x + math.cos(angle) * 1.5;
          final nextY = position.y + math.sin(angle) * 1.5;
          final checkX = nextX.floor();
          final checkY = nextY.floor();

          // If there's dirt blocking the path and ant has energy, dig toward food
          if (world.isInsideIndex(checkX, checkY) &&
              world.cellTypeAt(checkX, checkY) == CellType.dirt &&
              energy >= config.digEnergyCost) {
            _dig(world, checkX, checkY, config);
          }
          return;
        }
      }
    }

    // Small random wandering when no guidance at all
    if (!steered) {
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

  Map<String, dynamic> toJson() {
    return {
      'x': position.x,
      'y': position.y,
      'angle': angle,
      'state': state.index,
      'carryingFood': _carryingFood,
      'energy': energy,
      'stateBeforeRest': _stateBeforeRest?.index,
      'isExplorer': _isExplorer,
      'isEnemy': isEnemy,
      'attack': attack,
      'defense': defense,
      'maxHp': maxHp,
      'hp': hp,
    };
  }

  static Ant fromJson(Map<String, dynamic> json) {
    final stateIndex = (json['state'] as num?)?.toInt() ?? 0;
    final restIndex = (json['stateBeforeRest'] as num?)?.toInt();
    final clampedState = _clampStateIndex(stateIndex)!;
    final clampedRest = _clampStateIndex(restIndex);
    return Ant.rehydrated(
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
      isExplorer: json['isExplorer'] as bool? ?? false,
      isEnemy: json['isEnemy'] as bool? ?? false,
      attack: (json['attack'] as num?)?.toDouble() ?? 5,
      defense: (json['defense'] as num?)?.toDouble() ?? 2,
      maxHpValue: (json['maxHp'] as num?)?.toDouble() ?? 100,
      hp: (json['hp'] as num?)?.toDouble(),
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
