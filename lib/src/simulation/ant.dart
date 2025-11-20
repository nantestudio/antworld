import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

enum AntState { forage, returnHome }

class Ant {
  Ant({required Vector2 startPosition, required double initialAngle})
      : position = startPosition.clone(),
        angle = initialAngle;

  final Vector2 position;
  double angle;
  AntState state = AntState.forage;

  bool get hasFood => state == AntState.returnHome;

  bool update(
    double dt,
    SimulationConfig config,
    WorldGrid world,
    math.Random rng,
    double antSpeed,
  ) {
    if (dt == 0) return false;

    _steer(config, world, rng);

    final distance = antSpeed * dt;
    final vx = math.cos(angle) * distance;
    final vy = math.sin(angle) * distance;

    final nextX = position.x + vx;
    final nextY = position.y + vy;

    final gx = nextX.floor();
    final gy = nextY.floor();

    if (!world.isInsideIndex(gx, gy)) {
      angle += math.pi;
      return false;
    }

    final block = world.cellTypeAt(gx, gy);
    if (block == CellType.dirt) {
      angle += (rng.nextDouble() - 0.5) * 2 + math.pi;
      return false;
    }

    position.setValues(nextX, nextY);

    final depositX = position.x.floor();
    final depositY = position.y.floor();
    if (hasFood) {
      world.depositFoodPheromone(depositX, depositY, config.foodDepositStrength);
    } else {
      world.depositHomePheromone(depositX, depositY, config.homeDepositStrength);
    }

    if (block == CellType.food && !hasFood) {
      state = AntState.returnHome;
      world.removeFood(gx, gy);
      angle += config.foodPickupRotation + (rng.nextDouble() - 0.5) * 0.2;
    }

    final distNest = position.distanceTo(world.nestPosition);
    if (distNest < config.nestRadius + 0.5 && hasFood) {
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
    final sensorRight = _sense(angle + config.sensorAngle, config, world);
    final sensorFront = _sense(angle, config, world);
    final sensorLeft = _sense(angle - config.sensorAngle, config, world);

    if (sensorFront > sensorLeft && sensorFront > sensorRight) {
      angle += (rng.nextDouble() - 0.5) * 0.1;
    } else if (sensorLeft > sensorRight) {
      angle -= (rng.nextDouble() * 0.2 + 0.1);
    } else if (sensorRight > sensorLeft) {
      angle += (rng.nextDouble() * 0.2 + 0.1);
    } else {
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

    if (state == AntState.forage) {
      var value = world.foodPheromoneAt(gx, gy);
      if (world.cellTypeAt(gx, gy) == CellType.food) {
        value += 10;
      }
      return value;
    }

    return world.homePheromoneAt(gx, gy);
  }
}
