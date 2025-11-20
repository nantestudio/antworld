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
  })  : position = startPosition.clone(),
        _isExplorer = rng.nextDouble() < 0.05; // 5% are explorers

  Ant.rehydrated({
    required Vector2 position,
    required this.angle,
    required this.state,
    required bool carryingFood,
    required this.energy,
    AntState? stateBeforeRest,
    bool isExplorer = false,
  })  : position = position.clone(),
        _carryingFood = carryingFood,
        _stateBeforeRest = stateBeforeRest,
        _isExplorer = isExplorer;

  final Vector2 position;
  double angle;
  AntState state = AntState.forage;
  AntState? _stateBeforeRest;
  double energy;
  bool _carryingFood = false;
  int _consecutiveRockHits = 0;
  int _collisionCooldown = 0;
  double _speedMultiplier = 1.0;
  final bool _isExplorer; // 5% of ants are more random/exploratory

  bool get hasFood => _carryingFood;

  bool update(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
  ) {
    if (dt == 0) return false;

    if (state == AntState.rest) {
      _recoverEnergy(dt, config);
      return false;
    }

    energy -= config.energyDecayPerSecond * dt;
    if (energy <= 0) {
      energy = 0;
      _enterRest();
      return false;
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
          _collisionCooldown = 10; // Don't allow small steering adjustments for 10 frames
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
    if (world.isInsideIndex(depositX, depositY)) {
      if (hasFood) {
        // Vary deposit strength ±20% for natural trail variation
        final strength = config.foodDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositFoodPheromone(depositX, depositY, strength);
      } else {
        final strength = config.homeDepositStrength * (0.8 + rng.nextDouble() * 0.4);
        world.depositHomePheromone(depositX, depositY, strength);
      }
    }

    // Check for food at destination
    final destBlock = world.cellTypeAt(gx, gy);
    if (destBlock == CellType.food && !hasFood) {
      _carryingFood = true;
      state = AntState.returnHome;
      world.removeFood(gx, gy);
      angle += config.foodPickupRotation + (rng.nextDouble() - 0.5) * 0.2;
    }

    final distNest = position.distanceTo(world.nestPosition);
    if (distNest < config.nestRadius + 0.5 && hasFood) {
      _carryingFood = false;
      state = AntState.forage;
      angle += math.pi;
      return true;
    }

    return false;
  }

  void _steer(
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
  ) {
    // Skip steering during collision cooldown to commit to avoidance direction
    if (_collisionCooldown > 0) {
      return;
    }

    final behavior = state == AntState.rest && _stateBeforeRest != null
        ? _stateBeforeRest!
        : state;

    // Random exploration: explorers ignore pheromones more often (20% vs 1% chance)
    final exploreChance = _isExplorer ? 0.20 : 0.01;
    if (rng.nextDouble() < exploreChance) {
      angle += (rng.nextDouble() - 0.5) * 1.2; // Random turn ±0.6 rad
      return; // Skip normal pheromone following
    }

    // Add small random variation to sensor angles (±5% jitter)
    final angleJitter = config.sensorAngle * (rng.nextDouble() - 0.5) * 0.1;
    final sensorRight = _sense(angle + config.sensorAngle + angleJitter, config, world, rng);
    final sensorFront = _sense(angle + angleJitter * 0.5, config, world, rng);
    final sensorLeft = _sense(angle - config.sensorAngle + angleJitter, config, world, rng);

    bool steered = false;
    if (sensorFront > sensorLeft && sensorFront > sensorRight) {
      angle += (rng.nextDouble() - 0.5) * 0.1;
      steered = true;
    } else if (sensorLeft > sensorRight) {
      // Explorers make more mistakes (15% vs 3% chance)
      final mistakeChance = _isExplorer ? 0.15 : 0.03;
      final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
      angle -= (rng.nextDouble() * 0.2 + 0.1) * mistakeFactor;
      steered = true;
    } else if (sensorRight > sensorLeft) {
      final mistakeChance = _isExplorer ? 0.15 : 0.03;
      final mistakeFactor = rng.nextDouble() < mistakeChance ? 0.4 : 1.0;
      angle += (rng.nextDouble() * 0.2 + 0.1) * mistakeFactor;
      steered = true;
    }

    if (!steered && behavior == AntState.forage) {
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
          // Strategic digging toward sensed food
          _dig(world, checkX, checkY, config);
        }
        return;
      }
    }

    if (!steered) {
      angle += (rng.nextDouble() - 0.5) * 0.25;
    }
  }

  double _sense(double direction, SimulationConfig config, WorldGrid world, math.Random rng) {
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

  _PathCollision? _checkPathCollision(
    double x0,
    double y0,
    double x1,
    double y1,
    WorldGrid world,
  ) {
    // DDA-style raycast to check all cells along the movement path
    final dx = x1 - x0;
    final dy = y1 - y0;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance < 0.01) {
      return null; // Not moving
    }

    // Number of steps to check (at least check every 0.5 cells)
    final steps = (distance * 2).ceil();
    final stepX = dx / steps;
    final stepY = dy / steps;

    for (var i = 1; i <= steps; i++) {
      final checkX = x0 + stepX * i;
      final checkY = y0 + stepY * i;
      final cellX = checkX.floor();
      final cellY = checkY.floor();

      if (!world.isInsideIndex(cellX, cellY)) {
        continue; // Skip out of bounds checks
      }

      final cellType = world.cellTypeAt(cellX, cellY);
      if (cellType == CellType.dirt || cellType == CellType.rock) {
        return _PathCollision(
          cellX: cellX,
          cellY: cellY,
          cellType: cellType,
        );
      }
    }

    return null; // No collision
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
    if (energy <= 0) {
      _enterRest();
      return;
    }
    final spend = math.min(config.digEnergyCost, energy);
    final damage = spend * config.digDamagePerEnergy;
    world.damageDirt(gx, gy, damage);
    energy -= spend;
    if (energy <= 0) {
      energy = 0;
      _enterRest();
    }
  }

  void _recoverEnergy(double dt, SimulationConfig config) {
    energy += config.energyRecoveryPerSecond * dt;
    if (energy >= config.energyCapacity) {
      energy = config.energyCapacity;
      state = _stateBeforeRest ?? (hasFood ? AntState.returnHome : AntState.forage);
      _stateBeforeRest = null;
    }
  }

  void _enterRest() {
    if (state != AntState.rest) {
      _stateBeforeRest = state;
    }
    state = AntState.rest;
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
      stateBeforeRest:
          clampedRest == null ? null : AntState.values[clampedRest],
      isExplorer: json['isExplorer'] as bool? ?? false,
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
