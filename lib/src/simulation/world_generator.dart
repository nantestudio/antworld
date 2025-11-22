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
  // 4x original size (original was ~100x100)
  static const int defaultCols = 400;
  static const int defaultRows = 400;

  GeneratedWorld generate({
    required SimulationConfig baseConfig,
    required int seed,
  }) {
    final rng = math.Random(seed);
    final cols = defaultCols;
    final rows = defaultRows;
    final config = baseConfig.copyWith(cols: cols, rows: rows);
    final grid = WorldGrid(config);
    grid.reset(); // Fills entire grid with dirt

    // Carve the nest chamber first
    final nest = _carveNestChamber(grid, rng);

    // Carve tunnels and caverns into the dirt
    _carveMainTunnels(grid, rng, nest, cols, rows);
    _carveCaverns(grid, rng, cols, rows);

    // Add obstacles and food in carved areas
    _createRockFormations(grid, rng, cols, rows);
    _scatterFood(grid, rng, cols, rows);

    // Ensure solid dirt border around entire map
    _ensureDirtBorder(grid, 3);

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
    // Reduced: 15-25 tunnels with smaller radius to preserve more dirt
    final tunnelCount = rng.nextInt(10) + 15;
    for (var i = 0; i < tunnelCount; i++) {
      final start = nest + Vector2(
        (rng.nextDouble() - 0.5) * 10,
        (rng.nextDouble() - 0.5) * 10,
      );
      // Shorter tunnels with smaller radius
      _randomWalk(grid, rng, start, cols, rows,
          steps: rng.nextInt(180) + 150, radius: rng.nextInt(2) + 1);
    }
  }

  void _carveCaverns(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    // Reduced: 20-45 caverns with smaller radius
    final cavernCount = rng.nextInt(25) + 20;
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
    // Single large food source - forces ants to form clear pheromone highways
    // Place it away from nest (upper half of map) for interesting pathing
    final nestY = grid.nestPosition.y;
    final minDistFromNest = rows * 0.3; // At least 30% of map away from nest

    Vector2 pos;
    do {
      pos = _randomPoint(rng, cols, rows);
    } while ((pos.y - nestY).abs() < minDistFromNest);

    // Large radius (8-12) for a substantial food pile
    final radius = rng.nextInt(5) + 8;
    grid.placeFood(pos, radius);
  }

  /// Creates varied organic rock formations: roots, boulder clusters, and veins
  void _createRockFormations(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final formationCount = rng.nextInt(20) + 25; // 25-45 formations

    for (var i = 0; i < formationCount; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final type = rng.nextInt(10);

      if (type < 4) {
        // 40% - Root-like formations (tree roots, organic tendrils)
        _createRootFormation(grid, rng, pos, cols, rows);
      } else if (type < 7) {
        // 30% - Boulder clusters
        _createBoulderCluster(grid, rng, pos);
      } else {
        // 30% - Vein formations (mineral veins, long obstacles)
        _createVeinFormation(grid, rng, pos, cols, rows);
      }
    }
  }

  /// Creates a root-like rock formation with branches
  void _createRootFormation(
    WorldGrid grid,
    math.Random rng,
    Vector2 start,
    int cols,
    int rows,
  ) {
    var x = start.x;
    var y = start.y;
    var angle = rng.nextDouble() * math.pi * 2;
    final length = rng.nextInt(50) + 30; // 30-80 cells long
    final thickness = rng.nextInt(2) + 1; // 1-2 thickness

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();

      if (grid.isInsideIndex(gx, gy)) {
        // Place main root
        grid.setCell(gx, gy, CellType.rock);

        // Add thickness variation
        if (thickness > 1 || rng.nextDouble() < 0.4) {
          for (var t = 0; t < thickness; t++) {
            final ox = (rng.nextDouble() - 0.5) * 2;
            final oy = (rng.nextDouble() - 0.5) * 2;
            final nx = (gx + ox).round();
            final ny = (gy + oy).round();
            if (grid.isInsideIndex(nx, ny)) {
              grid.setCell(nx, ny, CellType.rock);
            }
          }
        }
      }

      // Create branch occasionally
      if (rng.nextDouble() < 0.08 && i > 5) {
        _createRootBranch(
          grid,
          rng,
          x,
          y,
          angle + (rng.nextBool() ? 0.7 : -0.7) + (rng.nextDouble() - 0.5) * 0.4,
          cols,
          rows,
        );
      }

      // Curve the root organically
      angle += (rng.nextDouble() - 0.5) * 0.35;
      x += math.cos(angle);
      y += math.sin(angle);

      // Stay in bounds
      x = x.clamp(2, cols - 3).toDouble();
      y = y.clamp(2, rows - 3).toDouble();
    }
  }

  /// Creates a branch off a root formation
  void _createRootBranch(
    WorldGrid grid,
    math.Random rng,
    double startX,
    double startY,
    double startAngle,
    int cols,
    int rows,
  ) {
    var x = startX;
    var y = startY;
    var angle = startAngle;
    final length = rng.nextInt(20) + 8; // Shorter branches

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();

      if (grid.isInsideIndex(gx, gy)) {
        grid.setCell(gx, gy, CellType.rock);

        // Occasional thickening
        if (rng.nextDouble() < 0.25) {
          final ox = (rng.nextDouble() - 0.5) * 1.5;
          final oy = (rng.nextDouble() - 0.5) * 1.5;
          final nx = (gx + ox).round();
          final ny = (gy + oy).round();
          if (grid.isInsideIndex(nx, ny)) {
            grid.setCell(nx, ny, CellType.rock);
          }
        }
      }

      // Sub-branch rarely
      if (rng.nextDouble() < 0.05 && i > 3) {
        _createTinyBranch(grid, rng, x, y, angle + (rng.nextBool() ? 0.8 : -0.8), cols, rows);
      }

      angle += (rng.nextDouble() - 0.5) * 0.5;
      x += math.cos(angle);
      y += math.sin(angle);
      x = x.clamp(2, cols - 3).toDouble();
      y = y.clamp(2, rows - 3).toDouble();
    }
  }

  /// Creates a tiny sub-branch
  void _createTinyBranch(
    WorldGrid grid,
    math.Random rng,
    double startX,
    double startY,
    double startAngle,
    int cols,
    int rows,
  ) {
    var x = startX;
    var y = startY;
    var angle = startAngle;
    final length = rng.nextInt(8) + 3;

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();
      if (grid.isInsideIndex(gx, gy)) {
        grid.setCell(gx, gy, CellType.rock);
      }
      angle += (rng.nextDouble() - 0.5) * 0.6;
      x += math.cos(angle);
      y += math.sin(angle);
    }
  }

  /// Creates a cluster of boulders
  void _createBoulderCluster(WorldGrid grid, math.Random rng, Vector2 center) {
    final count = rng.nextInt(5) + 3; // 3-7 boulders in cluster
    for (var i = 0; i < count; i++) {
      final offset = Vector2(
        (rng.nextDouble() - 0.5) * 12,
        (rng.nextDouble() - 0.5) * 12,
      );
      final pos = center + offset;
      final radius = rng.nextInt(3) + 1;
      grid.placeRock(pos, radius);
    }
  }

  /// Creates a long vein-like rock formation
  void _createVeinFormation(
    WorldGrid grid,
    math.Random rng,
    Vector2 start,
    int cols,
    int rows,
  ) {
    var x = start.x;
    var y = start.y;
    var angle = rng.nextDouble() * math.pi * 2;
    final length = rng.nextInt(80) + 40; // 40-120 cells long
    final waviness = rng.nextDouble() * 0.15 + 0.05; // How much it curves

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();

      if (grid.isInsideIndex(gx, gy)) {
        grid.setCell(gx, gy, CellType.rock);

        // Occasional widening
        if (rng.nextDouble() < 0.3) {
          // Perpendicular offset for width
          final perpAngle = angle + math.pi / 2;
          final side = rng.nextBool() ? 1 : -1;
          final nx = (gx + math.cos(perpAngle) * side).round();
          final ny = (gy + math.sin(perpAngle) * side).round();
          if (grid.isInsideIndex(nx, ny)) {
            grid.setCell(nx, ny, CellType.rock);
          }
        }
      }

      // Gentle curves
      angle += (rng.nextDouble() - 0.5) * waviness;
      x += math.cos(angle);
      y += math.sin(angle);
      x = x.clamp(2, cols - 3).toDouble();
      y = y.clamp(2, rows - 3).toDouble();
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
    final maxQueueSize = math.max(64, (cols * rows) ~/ 4);
    final maxCarveOps = math.max(cols * rows * 2, 2000);
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

        // Reduced branching
        final shouldBranch = taskRadius > 1 &&
            workQueue.length < maxQueueSize &&
            rng.nextDouble() < 0.06;
        if (shouldBranch) {
          final sideSteps = rng.nextInt(40) + 25;
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

  Vector2 _carveNestChamber(WorldGrid grid, math.Random rng) {
    // Position nest in the lower portion of the map
    final nestX = rng.nextInt(grid.cols - 80) + 40;
    final safeDepth = 20;
    final nestY = math.max(safeDepth, grid.rows - 35);
    final nest = Vector2(nestX.toDouble(), nestY.toDouble());
    grid.nestPosition.setFrom(nest);
    grid.digCircle(nest, grid.config.nestRadius + 4);
    grid.carveNest();
    grid.markHomeDistancesDirty();
    return nest;
  }

  /// Ensures a solid dirt border around the entire map edges
  void _ensureDirtBorder(WorldGrid grid, int borderWidth) {
    final cols = grid.cols;
    final rows = grid.rows;

    // Top and bottom borders
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < borderWidth; y++) {
        grid.setCell(x, y, CellType.dirt);
      }
      for (var y = rows - borderWidth; y < rows; y++) {
        grid.setCell(x, y, CellType.dirt);
      }
    }

    // Left and right borders
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < borderWidth; x++) {
        grid.setCell(x, y, CellType.dirt);
      }
      for (var x = cols - borderWidth; x < cols; x++) {
        grid.setCell(x, y, CellType.dirt);
      }
    }
  }
}
