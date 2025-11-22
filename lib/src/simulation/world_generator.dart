import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'world_grid.dart';

class _WalkTask {
  _WalkTask(this.x, this.y, this.angle, this.steps, this.radius);
  final double x;
  final double y;
  final double angle;
  final int steps;
  final int radius;
}

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
    final config = baseConfig.copyWith(cols: cols, rows: rows);
    final grid = WorldGrid(config);
    grid.reset();
    _buildSurfaceLayer(grid);
    final nest = _carveNestChamber(grid, rng);

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
    final workQueue = <_WalkTask>[
      _WalkTask(
        start.x,
        start.y,
        startAngle ?? rng.nextDouble() * math.pi * 2,
        steps,
        radius,
      ),
    ];
    final carvePos = Vector2.zero();
    final maxQueueSize = math.max(128, (cols * rows) ~/ 2);
    final maxCarveOps = math.max(cols * rows * 4, 2000);
    var carved = 0;

    while (workQueue.isNotEmpty && carved < maxCarveOps) {
      final task = workQueue.removeLast();
      var x = task.x;
      var y = task.y;
      var angle = task.angle;
      final taskRadius = task.radius;

      for (var i = 0; i < task.steps; i++) {
        carvePos.setValues(x, y);
        grid.digCircle(carvePos, taskRadius);
        carved++;
        if (carved >= maxCarveOps) {
          workQueue.clear();
          break;
        }

        angle += (rng.nextDouble() - 0.5) * 0.5;
        final distance = rng.nextDouble() * 2 + 0.5;
        x = (x + math.cos(angle) * distance).clamp(2, cols - 3).toDouble();
        y = (y + math.sin(angle) * distance).clamp(2, rows - 3).toDouble();

        final shouldBranch = taskRadius > 1 &&
            workQueue.length < maxQueueSize &&
            rng.nextDouble() < 0.08;
        if (shouldBranch) {
          final sideSteps = rng.nextInt(30) + 20;
          final sideAngle =
              angle + (rng.nextBool() ? math.pi / 2 : -math.pi / 2);
          workQueue.add(
            _WalkTask(
              x,
              y,
              sideAngle,
              sideSteps,
              math.max(1, taskRadius - 1),
            ),
          );
        }
      }
    }
  }

  Vector2 _randomPoint(math.Random rng, int cols, int rows) {
    return Vector2(
      rng.nextInt(cols - 4).toDouble() + 2,
      rng.nextInt(rows - 4).toDouble() + 2,
    );
  }

  void _buildSurfaceLayer(WorldGrid grid) {
    final surfaceDepth = 6;
    for (var y = 0; y < surfaceDepth && y < grid.rows; y++) {
      for (var x = 0; x < grid.cols; x++) {
        grid.setCell(x, y, CellType.air);
      }
    }
  }

  Vector2 _carveNestChamber(WorldGrid grid, math.Random rng) {
    final nestX = rng.nextInt(grid.cols - 20) + 10;
    final safeDepth = 8;
    final nestY = math.max(safeDepth, grid.rows - 12);
    final nest = Vector2(nestX.toDouble(), nestY.toDouble());
    grid.nestPosition.setFrom(nest);
    grid.digCircle(nest, grid.config.nestRadius + 3);
    grid.carveNest();
    grid.markHomeDistancesDirty();
    return nest;
  }
}
