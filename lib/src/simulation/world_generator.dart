import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

class GeneratedWorld {
  GeneratedWorld({
    required this.config,
    required this.world,
    required this.seed,
    required this.nestPosition,
  });

  final SimulationConfig config;
  final WorldGrid world;
  final int seed;
  final Vector2 nestPosition;
}

class WorldGenerator {
  GeneratedWorld generate({
    required SimulationConfig baseConfig,
    required int seed,
  }) {
    final rng = math.Random(seed);
    final cols = rng.nextInt(60) + 70; // 70-129
    final rows = rng.nextInt(50) + 70; // 70-119
    final nestX = rng.nextInt(cols - 20) + 10;
    final nestY = rng.nextInt(rows - 20) + 10;
    final config = baseConfig.copyWith(cols: cols, rows: rows);
    final nest = Vector2(nestX.toDouble(), nestY.toDouble());
    final grid = WorldGrid(config, nestOverride: nest);
    grid.reset();
    grid.carveNest();

    _carveMainTunnels(grid, rng, nest, cols, rows);
    _carveCaverns(grid, rng, cols, rows);
    _scatterFood(grid, rng, cols, rows);
    _scatterRocks(grid, rng, cols, rows);

    return GeneratedWorld(
      config: config,
      world: grid,
      seed: seed,
      nestPosition: nest,
    );
  }

  void _carveMainTunnels(
    WorldGrid grid,
    math.Random rng,
    Vector2 nest,
    int cols,
    int rows,
  ) {
    final tunnelCount = rng.nextInt(4) + 6;
    for (var i = 0; i < tunnelCount; i++) {
      final start = nest + Vector2(
        (rng.nextDouble() - 0.5) * 8,
        (rng.nextDouble() - 0.5) * 8,
      );
      _randomWalk(grid, rng, start, cols, rows,
          steps: rng.nextInt(200) + 160, radius: rng.nextInt(2) + 1);
    }
  }

  void _carveCaverns(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final cavernCount = rng.nextInt(15) + 10;
    for (var i = 0; i < cavernCount; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final radius = rng.nextInt(4) + 2;
      grid.digCircle(pos, radius);
    }
  }

  void _scatterFood(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final foodClusters = rng.nextInt(12) + 8;
    for (var i = 0; i < foodClusters; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final radius = rng.nextInt(3) + 2;
      grid.placeFood(pos, radius);
    }
  }

  void _scatterRocks(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final rockClusters = rng.nextInt(10) + 6;
    for (var i = 0; i < rockClusters; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final radius = rng.nextInt(3) + 1;
      grid.placeRock(pos, radius);
    }
  }

  void _randomWalk(
    WorldGrid grid,
    math.Random rng,
    Vector2 start,
    int cols,
    int rows, {
    required int steps,
    required int radius,
    double? startAngle,
  }) {
    var x = start.x;
    var y = start.y;
    var angle = startAngle ?? rng.nextDouble() * math.pi * 2;
    for (var i = 0; i < steps; i++) {
      grid.digCircle(Vector2(x, y), radius);
      angle += (rng.nextDouble() - 0.5) * 0.5;
      final distance = rng.nextDouble() * 2 + 0.5;
      x = (x + math.cos(angle) * distance).clamp(2, cols - 3).toDouble();
      y = (y + math.sin(angle) * distance).clamp(2, rows - 3).toDouble();
      if (rng.nextDouble() < 0.1) {
        final sideSteps = rng.nextInt(40) + 20;
        final sideAngle = angle + (rng.nextBool() ? math.pi / 2 : -math.pi / 2);
        _randomWalk(
          grid,
          rng,
          Vector2(x, y),
          cols,
          rows,
          steps: sideSteps,
          radius: math.max(1, radius - 1),
          startAngle: sideAngle,
        );
      }
    }
  }

  Vector2 _randomPoint(math.Random rng, int cols, int rows) {
    return Vector2(
      rng.nextInt(cols - 4).toDouble() + 2,
      rng.nextInt(rows - 4).toDouble() + 2,
    );
  }
}
