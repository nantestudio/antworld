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
    required this.nest1Position,
  });

  final SimulationConfig config;
  final WorldGrid world;
  final int seed;
  final Vector2 nestPosition;   // Colony 0 nest
  final Vector2 nest1Position;  // Colony 1 nest
}

class WorldGenerator {
  // Default map size - smaller for better performance
  static const int defaultCols = 150;
  static const int defaultRows = 150;

  // Preset map sizes
  static const Map<String, (int, int)> presets = {
    'Small': (100, 100),
    'Medium': (150, 150),
    'Large': (250, 250),
    'Huge': (400, 400),
  };

  GeneratedWorld generate({
    required SimulationConfig baseConfig,
    required int seed,
    int? cols,
    int? rows,
  }) {
    final rng = math.Random(seed);
    final actualCols = cols ?? defaultCols;
    final actualRows = rows ?? defaultRows;
    final config = baseConfig.copyWith(cols: actualCols, rows: actualRows);
    final grid = WorldGrid(config);
    grid.reset(); // Fills entire grid with dirt

    // Distribute dirt types based on distance from nests
    final tempNest0 = Vector2(actualCols * 0.75, actualRows * 0.75);
    final tempNest1 = Vector2(actualCols * 0.25, actualRows * 0.25);
    _distributeDirtTypes(grid, rng, tempNest0, tempNest1, actualCols, actualRows);

    // Carve both nest chambers on opposite corners
    final (nest0, nest1) = _carveDualNestChambers(grid, rng, actualCols, actualRows);

    // 1. First place rock formations (obstacles)
    _createRockFormations(grid, rng, actualCols, actualRows);

    // 2. Generate food positions first (so tunnels can connect to them)
    final foodPositions = _scatterFood(grid, rng, actualCols, actualRows);

    // 3. Carve tunnels from each nest to nearest food source
    _carveTunnelToFood(grid, nest0, foodPositions);
    _carveTunnelToFood(grid, nest1, foodPositions);

    // 4. Small caverns for exploration
    _carveCaverns(grid, rng, actualCols, actualRows);

    // Ensure solid dirt border around entire map
    _ensureDirtBorder(grid, 3);

    return GeneratedWorld(
      config: config,
      world: grid,
      seed: seed,
      nestPosition: nest0,
      nest1Position: nest1,
    );
  }

  /// Distribute dirt types based on distance from nests and noise
  void _distributeDirtTypes(
    WorldGrid grid,
    math.Random rng,
    Vector2 nest0,
    Vector2 nest1,
    int cols,
    int rows,
  ) {
    final nestRadius = grid.config.nestRadius;
    final maxDist = math.sqrt(cols * cols + rows * rows) * 0.5;

    // Pre-generate noise offsets for variation
    final noiseOffsetX = rng.nextDouble() * 1000;
    final noiseOffsetY = rng.nextDouble() * 1000;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (grid.cellTypeAt(x, y) != CellType.dirt) continue;

        final pos = Vector2(x.toDouble(), y.toDouble());
        final dist0 = pos.distanceTo(nest0);
        final dist1 = pos.distanceTo(nest1);
        final minDist = math.min(dist0, dist1);

        // Calculate base hardness from distance (0.0 = at nest, 1.0 = far away)
        final distFactor = (minDist / maxDist).clamp(0.0, 1.0);

        // Add pseudo-random noise for natural variation (simple hash-based noise)
        final noise = _simpleNoise(x + noiseOffsetX.toInt(), y + noiseOffsetY.toInt());

        // Combine distance and noise
        final combined = distFactor * 0.7 + noise * 0.3;

        // Determine dirt type based on combined value and distance zones
        DirtType type;
        if (minDist < nestRadius * 3) {
          // Safety zone: only soft sand or loose soil
          type = combined < 0.5 ? DirtType.softSand : DirtType.looseSoil;
        } else if (minDist < nestRadius * 5) {
          // Transition zone: soft to packed
          if (combined < 0.3) {
            type = DirtType.softSand;
          } else if (combined < 0.6) {
            type = DirtType.looseSoil;
          } else {
            type = DirtType.packedEarth;
          }
        } else if (minDist < nestRadius * 8) {
          // Mid zone: loose to clay
          if (combined < 0.2) {
            type = DirtType.looseSoil;
          } else if (combined < 0.5) {
            type = DirtType.packedEarth;
          } else if (combined < 0.85) {
            type = DirtType.clay;
          } else {
            // Rare hardite veins (15% in this zone)
            type = DirtType.hardite;
          }
        } else {
          // Outer zone: can have all types, biased toward harder
          if (combined < 0.15) {
            type = DirtType.looseSoil;
          } else if (combined < 0.35) {
            type = DirtType.packedEarth;
          } else if (combined < 0.7) {
            type = DirtType.clay;
          } else {
            type = DirtType.hardite;
          }
        }

        grid.setDirtType(x, y, type);
      }
    }
  }

  /// Simple hash-based noise function (0.0 to 1.0)
  double _simpleNoise(int x, int y) {
    // Simple hash mixing
    var h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0x7FFFFFFF) / 0x7FFFFFFF;
  }

  void _carveCaverns(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    // Minimal caverns - small pockets for ants to discover
    final cavernCount = rng.nextInt(8) + 5; // Only 5-12 small caverns
    for (var i = 0; i < cavernCount; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final radius = rng.nextInt(2) + 1; // Small radius 1-2
      grid.digCircle(pos, radius);
    }
  }

  /// Scatters food clusters and returns their positions
  List<Vector2> _scatterFood(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final foodPositions = <Vector2>[];

    // Place food sources away from both nests
    final nest0 = grid.nestPosition;
    final nest1 = grid.nest1Position;
    final minDistFromNest = rows * 0.2; // At least 20% of map away from nests

    // Place 2-3 food clusters
    final foodCount = rng.nextInt(2) + 2;
    for (var i = 0; i < foodCount; i++) {
      Vector2 pos;
      var attempts = 0;
      do {
        pos = _randomPoint(rng, cols, rows);
        attempts++;
      } while (attempts < 50 &&
               (pos.distanceTo(nest0) < minDistFromNest ||
                pos.distanceTo(nest1) < minDistFromNest));

      // Carve out space first so food can be placed
      final radius = rng.nextInt(3) + 4; // Radius 4-6
      grid.digCircle(pos, radius);
      // Now place food in the carved space
      grid.placeFood(pos, radius);
      foodPositions.add(pos);
    }

    return foodPositions;
  }

  /// Carves a 2-cell-wide tunnel with sharp corners from nest to the nearest food source
  void _carveTunnelToFood(WorldGrid grid, Vector2 nest, List<Vector2> foodPositions) {
    if (foodPositions.isEmpty) return;

    // Find nearest food
    Vector2? nearestFood;
    var nearestDist = double.infinity;
    for (final food in foodPositions) {
      final dist = nest.distanceTo(food);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestFood = food;
      }
    }

    if (nearestFood == null) return;

    final rng = math.Random(nest.x.toInt() ^ nest.y.toInt());

    // Generate 4-6 waypoints with sharp corners between nest and food
    final waypoints = <Vector2>[nest.clone()];
    final numCorners = rng.nextInt(3) + 4; // 4-6 corners

    for (var i = 1; i <= numCorners; i++) {
      final t = i / (numCorners + 1); // Progress from 0 to 1
      // Base position along direct line
      final baseX = nest.x + (nearestFood.x - nest.x) * t;
      final baseY = nest.y + (nearestFood.y - nest.y) * t;

      // Add significant perpendicular offset for sharp corners
      final perpX = -(nearestFood.y - nest.y);
      final perpY = nearestFood.x - nest.x;
      final perpLen = math.sqrt(perpX * perpX + perpY * perpY);
      if (perpLen > 0) {
        final offsetStrength = (rng.nextDouble() - 0.5) * nearestDist * 0.4; // Up to 40% of distance
        final wx = baseX + (perpX / perpLen) * offsetStrength;
        final wy = baseY + (perpY / perpLen) * offsetStrength;
        waypoints.add(Vector2(wx, wy));
      } else {
        waypoints.add(Vector2(baseX, baseY));
      }
    }
    waypoints.add(nearestFood.clone());

    // Carve tunnel through all waypoints
    for (var i = 0; i < waypoints.length - 1; i++) {
      _carveSegment(grid, waypoints[i], waypoints[i + 1]);
    }
  }

  /// Carves a 2-cell-wide straight segment between two points
  void _carveSegment(WorldGrid grid, Vector2 from, Vector2 to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    final stepX = dx / dist;
    final stepY = dy / dist;
    final perpX = -stepY;
    final perpY = stepX;
    final steps = dist.ceil();

    var x = from.x;
    var y = from.y;

    for (var i = 0; i <= steps; i++) {
      // Carve 2 cells wide
      for (var w = 0; w < 2; w++) {
        final gx = (x + perpX * w).round();
        final gy = (y + perpY * w).round();

        if (grid.isInsideIndex(gx, gy)) {
          final cellType = grid.cellTypeAt(gx, gy);
          if (cellType == CellType.dirt) {
            grid.setCell(gx, gy, CellType.air);
          }
        }
      }

      x += stepX;
      y += stepY;
    }
  }

  /// Creates varied organic rock formations: roots, boulder clusters, and veins
  void _createRockFormations(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    // Reduced: 8-15 formations (was 25-45) for better navigation
    final formationCount = rng.nextInt(8) + 8;

    for (var i = 0; i < formationCount; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final type = rng.nextInt(10);

      if (type < 3) {
        // 30% - Root-like formations (tree roots, organic tendrils)
        _createRootFormation(grid, rng, pos, cols, rows);
      } else if (type < 7) {
        // 40% - Boulder clusters (smaller, less blocking)
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
    final length = rng.nextInt(25) + 15; // 15-40 cells long

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();

      if (grid.isInsideIndex(gx, gy)) {
        // Place main root with 2-cell thickness perpendicular to direction
        _placeThickLine(grid, gx, gy, angle);
      }

      // Create branch occasionally (reduced from 8% to 3%)
      if (rng.nextDouble() < 0.03 && i > 5) {
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

  /// Places a 2-cell thick rock perpendicular to the given angle
  void _placeThickLine(WorldGrid grid, int gx, int gy, double angle) {
    grid.setCell(gx, gy, CellType.rock);
    // Add perpendicular cell for 2-block thickness
    final perpAngle = angle + math.pi / 2;
    final nx = (gx + math.cos(perpAngle)).round();
    final ny = (gy + math.sin(perpAngle)).round();
    if (grid.isInsideIndex(nx, ny)) {
      grid.setCell(nx, ny, CellType.rock);
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
        // 2-cell thick branch
        _placeThickLine(grid, gx, gy, angle);
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
        // 2-cell thick even for tiny branches
        _placeThickLine(grid, gx, gy, angle);
      }
      angle += (rng.nextDouble() - 0.5) * 0.6;
      x += math.cos(angle);
      y += math.sin(angle);
    }
  }

  /// Creates a cluster of boulders
  void _createBoulderCluster(WorldGrid grid, math.Random rng, Vector2 center) {
    final count = rng.nextInt(3) + 2; // 2-4 boulders in cluster (was 3-7)
    for (var i = 0; i < count; i++) {
      final offset = Vector2(
        (rng.nextDouble() - 0.5) * 10,
        (rng.nextDouble() - 0.5) * 10,
      );
      final pos = center + offset;
      final radius = rng.nextInt(2) + 1; // 1-2 radius (was 1-3)
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
    final length = rng.nextInt(30) + 20; // 20-50 cells long
    final waviness = rng.nextDouble() * 0.15 + 0.05; // How much it curves

    for (var i = 0; i < length; i++) {
      final gx = x.round();
      final gy = y.round();

      if (grid.isInsideIndex(gx, gy)) {
        // Always 2-cell thick vein
        _placeThickLine(grid, gx, gy, angle);

        // Occasional extra widening (makes some sections 3 cells)
        if (rng.nextDouble() < 0.15) {
          final perpAngle = angle + math.pi / 2;
          final side = rng.nextBool() ? 2 : -2;
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

  Vector2 _randomPoint(math.Random rng, int cols, int rows) {
    return Vector2(
      rng.nextInt(cols - 4).toDouble() + 2,
      rng.nextInt(rows - 4).toDouble() + 2,
    );
  }

  /// Creates two nest chambers on opposite corners of the map
  (Vector2, Vector2) _carveDualNestChambers(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
  ) {
    final safeMargin = 25; // Distance from edges
    final nestRadius = grid.config.nestRadius;

    // Colony 0 nest: bottom-left area
    final nest0X = safeMargin + rng.nextInt(20);
    final nest0Y = rows - safeMargin - rng.nextInt(20);
    final nest0 = Vector2(nest0X.toDouble(), nest0Y.toDouble());

    // Colony 1 nest: top-right area
    final nest1X = cols - safeMargin - rng.nextInt(20);
    final nest1Y = safeMargin + rng.nextInt(20);
    final nest1 = Vector2(nest1X.toDouble(), nest1Y.toDouble());

    // Set positions in grid
    grid.nestPosition.setFrom(nest0);
    grid.nest1Position.setFrom(nest1);

    // Dig initial chambers
    grid.digCircle(nest0, nestRadius + 4);
    grid.digCircle(nest1, nestRadius + 4);

    // Carve zone rings for both nests
    grid.carveNest();
    grid.markHomeDistancesDirty();

    return (nest0, nest1);
  }

  /// Ensures a solid dirt border around the entire map edges
  void _ensureDirtBorder(WorldGrid grid, int borderWidth) {
    final cols = grid.cols;
    final rows = grid.rows;

    // Top and bottom borders - use hardite for hard boundary
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < borderWidth; y++) {
        grid.setCell(x, y, CellType.dirt, dirtType: DirtType.hardite);
      }
      for (var y = rows - borderWidth; y < rows; y++) {
        grid.setCell(x, y, CellType.dirt, dirtType: DirtType.hardite);
      }
    }

    // Left and right borders
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < borderWidth; x++) {
        grid.setCell(x, y, CellType.dirt, dirtType: DirtType.hardite);
      }
      for (var x = cols - borderWidth; x < cols; x++) {
        grid.setCell(x, y, CellType.dirt, dirtType: DirtType.hardite);
      }
    }
  }
}
