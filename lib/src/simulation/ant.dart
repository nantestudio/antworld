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
  }) : position = startPosition.clone();

  Ant.rehydrated({
    required Vector2 position,
    required this.angle,
    required this.state,
    required bool carryingFood,
    required this.energy,
    AntState? stateBeforeRest,
  })  : position = position.clone(),
        _carryingFood = carryingFood,
        _stateBeforeRest = stateBeforeRest;

  final Vector2 position;
  double angle;
  AntState state = AntState.forage;
  AntState? _stateBeforeRest;
  double energy;
  bool _carryingFood = false;

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

    _steer(config, world, rng);

    final distance = antSpeed * dt;
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
      } else if (hitBlock == CellType.rock) {
        angle += math.pi + (rng.nextDouble() - 0.5) * 0.6;
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

    final depositX = position.x.floor();
    final depositY = position.y.floor();
    if (world.isInsideIndex(depositX, depositY)) {
      if (hasFood) {
        world.depositFoodPheromone(depositX, depositY, config.foodDepositStrength);
      } else {
        world.depositHomePheromone(depositX, depositY, config.homeDepositStrength);
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
    final behavior = state == AntState.rest && _stateBeforeRest != null
        ? _stateBeforeRest!
        : state;
    final sensorRight = _sense(angle + config.sensorAngle, config, world);
    final sensorFront = _sense(angle, config, world);
    final sensorLeft = _sense(angle - config.sensorAngle, config, world);

    bool steered = false;
    if (sensorFront > sensorLeft && sensorFront > sensorRight) {
      angle += (rng.nextDouble() - 0.5) * 0.1;
      steered = true;
    } else if (sensorLeft > sensorRight) {
      angle -= (rng.nextDouble() * 0.2 + 0.1);
      steered = true;
    } else if (sensorRight > sensorLeft) {
      angle += (rng.nextDouble() * 0.2 + 0.1);
      steered = true;
    }

    if (!steered && behavior == AntState.forage) {
      if (_biasTowardFood(world, config, rng)) {
        return;
      }
    }

    if (!steered) {
      angle += (rng.nextDouble() - 0.5) * 0.25;
    }
  }

  double _sense(double direction, SimulationConfig config, WorldGrid world) {
    final sx = position.x + math.cos(direction) * config.sensorDistance;
    final sy = position.y + math.sin(direction) * config.sensorDistance;
    final gx = sx.floor();
    final gy = sy.floor();

    if (!world.isInsideIndex(gx, gy)) {
      return -1;
    }
    if (world.cellTypeAt(gx, gy) == CellType.dirt) {
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
      return value;
    }

    return world.homePheromoneAt(gx, gy);
  }

  bool _biasTowardFood(
    WorldGrid world,
    SimulationConfig config,
    math.Random rng,
  ) {
    final target = world.nearestFood(position, config.foodSenseRange);
    if (target == null) {
      return false;
    }
    final desired = math.atan2(target.y - position.y, target.x - position.x);
    final delta = _normalizeAngle(desired - angle);
    angle += delta.clamp(-0.3, 0.3) * 0.4;
    angle += (rng.nextDouble() - 0.5) * 0.05;
    return true;
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
