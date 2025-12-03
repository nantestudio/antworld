import 'dart:math' as math;

import 'package:flame/components.dart';

import 'simulation_config.dart';
import 'level_layout.dart';
import 'world_grid.dart';

class GeneratedWorld {
  GeneratedWorld({
    required this.config,
    required this.world,
    required this.seed,
    required this.nestPositions,
  });

  final SimulationConfig config;
  final WorldGrid world;
  final int seed;
  final List<Vector2> nestPositions; // One per colony

  // Legacy accessors for compatibility
  Vector2 get nestPosition =>
      nestPositions.isNotEmpty ? nestPositions[0] : Vector2.zero();
  Vector2 get nest1Position =>
      nestPositions.length > 1 ? nestPositions[1] : nestPositions[0];
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
    int? colonyCount,
    LevelLayout? layout,
  }) {
    final effectiveSeed = layout?.seed ?? seed;
    final rng = math.Random(effectiveSeed);
    final actualCols = layout?.cols ?? cols ?? defaultCols;
    final actualRows = layout?.rows ?? rows ?? defaultRows;
    final actualColonyCount =
        (layout?.colonyCount ?? colonyCount ?? baseConfig.colonyCount).clamp(
          1,
          4,
        );
    final config = baseConfig.copyWith(
      cols: actualCols,
      rows: actualRows,
      colonyCount: actualColonyCount,
    );
    final grid = WorldGrid(config);
    grid.reset(); // Fills entire grid with dirt

    final biome = layout?.biome ?? const BiomeSettings();

    // Distribute dirt types based on distance from nests
    final tempNest0 = Vector2(actualCols * 0.75, actualRows * 0.75);
    final tempNest1 = Vector2(actualCols * 0.25, actualRows * 0.25);
    _distributeDirtTypes(
      grid,
      rng,
      tempNest0,
      tempNest1,
      actualCols,
      actualRows,
      hardnessBias: biome.hardnessBias,
    );

    // Carve nest chambers for all colonies
    final nestPositions = _carveNestChambers(
      grid,
      rng,
      actualCols,
      actualRows,
      actualColonyCount,
      overrides: layout?.nestPositions,
    );

    _applyAnchors(grid, layout);

    // 1. First place rock formations (obstacles)
    _createRockFormations(
      grid,
      rng,
      actualCols,
      actualRows,
      countOverride: biome.rockFormations,
    );

    // 2. Generate food clusters (distant from nests - ants must dig to find)
    _scatterFood(
      grid,
      rng,
      actualCols,
      actualRows,
      countOverride: biome.foodClusters,
      minDistFactor: biome.minFoodDistanceFactor,
      overridePositions: layout?.foodOverride,
    );

    // 3. Create starter area around each nest (small, ants must dig to expand)
    for (final nest in nestPositions) {
      _carveStarterArea(grid, rng, nest);
      _placeStarterFoodNearNest(grid, rng, nest);
    }

    // 4. Add terrain features for exploration
    _generateTerrainFeatures(grid, rng, actualCols, actualRows, biome);

    // 5. Small caverns for exploration
    _carveCaverns(
      grid,
      rng,
      actualCols,
      actualRows,
      countOverride: biome.caverns,
    );

    // Ensure solid dirt border around entire map
    _ensureDirtBorder(grid, 3);

    return GeneratedWorld(
      config: config,
      world: grid,
      seed: effectiveSeed,
      nestPositions: nestPositions,
    );
  }

  /// Distribute dirt types based on distance from nests and noise
  void _distributeDirtTypes(
    WorldGrid grid,
    math.Random rng,
    Vector2 nest0,
    Vector2 nest1,
    int cols,
    int rows, {
    double hardnessBias = 1.0,
  }) {
    final nestRadius = grid.config.nestRadius;
    final maxDist = math.sqrt(cols * cols + rows * rows) * 0.5 * hardnessBias;

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
        final noise = _simpleNoise(
          x + noiseOffsetX.toInt(),
          y + noiseOffsetY.toInt(),
        );

        // Combine distance and noise
        final combined = distFactor * 0.7 + noise * 0.3;

        // Determine dirt type based on combined value and distance zones
        DirtType type;
        if (minDist < nestRadius * 3.5) {
          // Safety zone: soft sand predominates, no hardite
          type = combined < 0.65 ? DirtType.softSand : DirtType.looseSoil;
        } else if (minDist < nestRadius * 5.5) {
          // Transition zone: introduce packed earth but keep it diggable
          if (combined < 0.35) {
            type = DirtType.softSand;
          } else if (combined < 0.7) {
            type = DirtType.looseSoil;
          } else {
            type = DirtType.packedEarth;
          }
        } else if (minDist < nestRadius * 8) {
          // Mid zone: loose to clay, rare hardite seams
          if (combined < 0.2) {
            type = DirtType.looseSoil;
          } else if (combined < 0.55) {
            type = DirtType.packedEarth;
          } else if (combined < 0.9) {
            type = DirtType.clay;
          } else {
            type = DirtType.hardite;
          }
        } else {
          // Outer zone: harder mix but still limited hardite
          if (combined < 0.2) {
            type = DirtType.looseSoil;
          } else if (combined < 0.4) {
            type = DirtType.packedEarth;
          } else if (combined < 0.75) {
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

  void _placeStarterFoodNearNest(
    WorldGrid grid,
    math.Random rng,
    Vector2 nest,
  ) {
    final angle = rng.nextDouble() * math.pi * 2;
    final distance = grid.config.nestRadius + 3 + rng.nextDouble() * 3;
    final pos = Vector2(
      (nest.x + math.cos(angle) * distance).clamp(2, grid.cols - 3),
      (nest.y + math.sin(angle) * distance).clamp(2, grid.rows - 3),
    );
    grid.placeFood(pos, 2, amount: WorldGrid.defaultFoodPerCell ~/ 2);
  }

  /// Carves a small starter area around the nest for initial exploration
  /// This replaces the pre-carved tunnels to force ants to dig
  void _carveStarterArea(WorldGrid grid, math.Random rng, Vector2 nest) {
    const starterRadius = 8; // Small radius around nest

    // Carve circular starter area with soft dirt on edges
    for (var dy = -starterRadius; dy <= starterRadius; dy++) {
      for (var dx = -starterRadius; dx <= starterRadius; dx++) {
        final distSq = dx * dx + dy * dy;
        if (distSq > starterRadius * starterRadius) continue;

        final x = (nest.x + dx).floor();
        final y = (nest.y + dy).floor();
        if (!grid.isInsideIndex(x, y)) continue;

        final dist = math.sqrt(distSq.toDouble());

        // Inner area (radius < 5): clear air
        if (dist < 5) {
          grid.setCell(x, y, CellType.air);
        }
        // Outer ring: soft dirt for easy initial digging
        else {
          grid.setCell(x, y, CellType.dirt, dirtType: DirtType.softSand);
        }
      }
    }
  }

  /// Generate terrain features to make maps more interesting
  void _generateTerrainFeatures(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
    BiomeSettings biome,
  ) {
    // Aquifer zones - pockets of soft sand (easy-dig shortcuts)
    _generateAquiferZones(grid, rng, cols, rows, count: 4);

    // Hidden chambers - sealed spaces with potential treasures
    _generateHiddenChambers(grid, rng, cols, rows, count: 2);

    // Resource veins - lines of food embedded in walls
    _generateResourceVeins(grid, rng, cols, rows, count: 5);

    // Hard barriers - bedrock walls that require going around
    _generateHardBarriers(grid, rng, cols, rows, count: 2);
  }

  /// Create pockets of soft sand (aquifer zones) - easy to dig through
  void _generateAquiferZones(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    required int count,
  }) {
    for (var i = 0; i < count; i++) {
      final pos = _randomPoint(rng, cols, rows);
      final radius = rng.nextInt(8) + 6; // 6-13 radius

      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue;

          final x = (pos.x + dx).floor();
          final y = (pos.y + dy).floor();
          if (!grid.isInsideIndex(x, y)) continue;

          // Only convert dirt cells
          if (grid.cellTypeAt(x, y) == CellType.dirt) {
            grid.setCell(x, y, CellType.dirt, dirtType: DirtType.softSand);
          }
        }
      }
    }
  }

  /// Create hidden sealed chambers with treasure potential
  void _generateHiddenChambers(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    required int count,
  }) {
    final nests = grid.nestPositions;

    for (var i = 0; i < count; i++) {
      // Find position far from nests
      Vector2 pos;
      var attempts = 0;
      do {
        pos = _randomPoint(rng, cols, rows);
        attempts++;

        var tooClose = false;
        for (final nest in nests) {
          if (pos.distanceTo(nest) < rows * 0.3) {
            tooClose = true;
            break;
          }
        }
        if (!tooClose) break;
      } while (attempts < 50);

      if (attempts >= 50) continue;

      final radius = rng.nextInt(3) + 4; // 4-6 radius

      // First surround with hard rock wall
      for (var dy = -radius - 2; dy <= radius + 2; dy++) {
        for (var dx = -radius - 2; dx <= radius + 2; dx++) {
          final distSq = dx * dx + dy * dy;
          final outerRadius = (radius + 2) * (radius + 2);
          final innerRadius = radius * radius;

          final x = (pos.x + dx).floor();
          final y = (pos.y + dy).floor();
          if (!grid.isInsideIndex(x, y)) continue;

          // Create hardite wall around chamber
          if (distSq <= outerRadius && distSq > innerRadius) {
            grid.setCell(x, y, CellType.dirt, dirtType: DirtType.hardite);
          }
          // Interior is air
          else if (distSq <= innerRadius) {
            grid.setCell(x, y, CellType.air);
          }
        }
      }

      // Place treasure food inside (30% of cells)
      for (var dy = -radius ~/ 2; dy <= radius ~/ 2; dy++) {
        for (var dx = -radius ~/ 2; dx <= radius ~/ 2; dx++) {
          if (rng.nextDouble() < 0.3) {
            final x = (pos.x + dx).floor();
            final y = (pos.y + dy).floor();
            if (grid.isInsideIndex(x, y)) {
              grid.setCell(x, y, CellType.food);
            }
          }
        }
      }
    }
  }

  /// Create lines of food cells embedded in walls
  void _generateResourceVeins(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    required int count,
  }) {
    for (var i = 0; i < count; i++) {
      final start = _randomPoint(rng, cols, rows);
      var angle = rng.nextDouble() * math.pi * 2;
      final length = rng.nextInt(20) + 10; // 10-30 cells

      var x = start.x;
      var y = start.y;

      for (var j = 0; j < length; j++) {
        final gx = x.round();
        final gy = y.round();

        if (grid.isInsideIndex(gx, gy)) {
          final cell = grid.cellTypeAt(gx, gy);
          // Only place food in dirt cells (don't replace air/rock)
          if (cell == CellType.dirt) {
            grid.setCell(gx, gy, CellType.food);
          }
        }

        // Gentle curve
        angle += (rng.nextDouble() - 0.5) * 0.3;
        x += math.cos(angle);
        y += math.sin(angle);
      }
    }
  }

  /// Create bedrock barriers that require strategic routing
  void _generateHardBarriers(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    required int count,
  }) {
    for (var i = 0; i < count; i++) {
      final start = _randomPoint(rng, cols, rows);
      var angle = rng.nextDouble() * math.pi * 2;
      final length = rng.nextInt(30) + 15; // 15-45 cells
      const thickness = 3;

      var x = start.x;
      var y = start.y;

      for (var j = 0; j < length; j++) {
        final gx = x.round();
        final gy = y.round();

        // Create thick bedrock wall
        for (var t = -thickness ~/ 2; t <= thickness ~/ 2; t++) {
          final perpAngle = angle + math.pi / 2;
          final tx = (gx + math.cos(perpAngle) * t).round();
          final ty = (gy + math.sin(perpAngle) * t).round();

          if (grid.isInsideIndex(tx, ty)) {
            final cell = grid.cellTypeAt(tx, ty);
            // Only replace dirt, not air or food
            if (cell == CellType.dirt) {
              grid.setCell(tx, ty, CellType.dirt, dirtType: DirtType.bedrock);
            }
          }
        }

        // Gentle curve
        angle += (rng.nextDouble() - 0.5) * 0.2;
        x += math.cos(angle);
        y += math.sin(angle);
        x = x.clamp(5, cols - 5).toDouble();
        y = y.clamp(5, rows - 5).toDouble();
      }
    }
  }

  void _carveCaverns(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    int? countOverride,
  }) {
    // Minimal caverns - small pockets for ants to discover
    final base = countOverride ?? 0;
    final cavernCount = base > 0
        ? base
        : rng.nextInt(8) + 5; // Only 5-12 small caverns
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
    int rows, {
    int? countOverride,
    double? minDistFactor,
    List<Vector2>? overridePositions,
  }) {
    final foodPositions = <Vector2>[];
    if (overridePositions != null && overridePositions.isNotEmpty) {
      for (final pos in overridePositions) {
        final clamped = Vector2(
          pos.x.clamp(2, cols - 3),
          pos.y.clamp(2, rows - 3),
        );
        final radius = rng.nextInt(3) + 4; // Radius 4-6
        grid.digCircle(clamped, radius);
        grid.placeFood(clamped, radius);
        foodPositions.add(clamped);
      }
      return foodPositions;
    }

    // Place food sources away from both nests
    final nest0 = grid.nestPosition;
    final nest1 = grid.nest1Position;
    final minDistFromNest =
        rows * (minDistFactor ?? 0.2); // At least 20% of map away from nests

    final clusterCount = countOverride ?? 3;

    // Place food clusters initially - spread across the map
    for (var i = 0; i < clusterCount; i++) {
      Vector2 pos;
      var attempts = 0;
      do {
        pos = _randomPoint(rng, cols, rows);
        attempts++;
        // Also check distance from other food positions
        var tooCloseToOtherFood = false;
        for (final otherFood in foodPositions) {
          if (pos.distanceTo(otherFood) < cols * 0.2) {
            tooCloseToOtherFood = true;
            break;
          }
        }
        if (tooCloseToOtherFood) continue;
      } while (attempts < 100 &&
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

  /// Creates varied organic rock formations: roots, boulder clusters, and veins
  void _createRockFormations(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows, {
    int? countOverride,
  }) {
    // Reduced: 8-15 formations (was 25-45) for better navigation
    final formationCount = countOverride ?? (rng.nextInt(8) + 8);

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
          angle +
              (rng.nextBool() ? 0.7 : -0.7) +
              (rng.nextDouble() - 0.5) * 0.4,
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

  /// Places a 2-cell thick hardite perpendicular to the given angle
  void _placeThickLine(WorldGrid grid, int gx, int gy, double angle) {
    grid.setCell(gx, gy, CellType.dirt, dirtType: DirtType.hardite);
    // Add perpendicular cell for 2-block thickness
    final perpAngle = angle + math.pi / 2;
    final nx = (gx + math.cos(perpAngle)).round();
    final ny = (gy + math.sin(perpAngle)).round();
    if (grid.isInsideIndex(nx, ny)) {
      grid.setCell(nx, ny, CellType.dirt, dirtType: DirtType.hardite);
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
        _createTinyBranch(
          grid,
          rng,
          x,
          y,
          angle + (rng.nextBool() ? 0.8 : -0.8),
          cols,
          rows,
        );
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

  /// Creates a cluster of hardite boulders (diggable but tough)
  void _createBoulderCluster(WorldGrid grid, math.Random rng, Vector2 center) {
    final count = rng.nextInt(3) + 2; // 2-4 boulders in cluster (was 3-7)
    for (var i = 0; i < count; i++) {
      final offset = Vector2(
        (rng.nextDouble() - 0.5) * 10,
        (rng.nextDouble() - 0.5) * 10,
      );
      final pos = center + offset;
      final radius = rng.nextInt(2) + 1; // 1-2 radius (was 1-3)
      grid.placeHardite(pos, radius);
    }
  }

  /// Creates a long vein-like hardite formation (diggable but tough)
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
            grid.setCell(nx, ny, CellType.dirt, dirtType: DirtType.hardite);
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

  void _applyAnchors(WorldGrid grid, LevelLayout? layout) {
    if (layout == null || layout.anchors.isEmpty) return;
    const margin = 2;
    for (final anchor in layout.anchors) {
      final pos = Vector2(
        anchor.position.x.clamp(margin, grid.cols - margin).toDouble(),
        anchor.position.y.clamp(margin, grid.rows - margin).toDouble(),
      );
      switch (anchor.type) {
        case LayoutAnchorType.tunnelWaypoint:
          grid.digCircle(pos, anchor.radius.ceil());
          break;
        case LayoutAnchorType.cavern:
          grid.digCircle(pos, anchor.radius.ceil());
          break;
        case LayoutAnchorType.harditeWall:
          grid.placeHardite(pos, anchor.radius.ceil());
          break;
      }
    }
  }

  Vector2 _randomPoint(math.Random rng, int cols, int rows) {
    return Vector2(
      rng.nextInt(cols - 4).toDouble() + 2,
      rng.nextInt(rows - 4).toDouble() + 2,
    );
  }

  /// Carve nest chambers for 1-4 colonies, positioned at map corners
  List<Vector2> _carveNestChambers(
    WorldGrid grid,
    math.Random rng,
    int cols,
    int rows,
    int colonyCount, {
    List<Vector2>? overrides,
  }) {
    final safeMargin = 25;
    final nestPositions = <Vector2>[];

    // Position colonies at corners based on count
    // 1 colony: bottom-left
    // 2 colonies: bottom-left, top-right (diagonal)
    // 3 colonies: bottom-left, top-right, top-left
    // 4 colonies: all four corners
    final cornerPositions =
        overrides ??
        [
          Vector2(
            (safeMargin + rng.nextInt(20)).toDouble(),
            (rows - safeMargin - rng.nextInt(20)).toDouble(),
          ), // bottom-left
          Vector2(
            (cols - safeMargin - rng.nextInt(20)).toDouble(),
            (safeMargin + rng.nextInt(20)).toDouble(),
          ), // top-right
          Vector2(
            (safeMargin + rng.nextInt(20)).toDouble(),
            (safeMargin + rng.nextInt(20)).toDouble(),
          ), // top-left
          Vector2(
            (cols - safeMargin - rng.nextInt(20)).toDouble(),
            (rows - safeMargin - rng.nextInt(20)).toDouble(),
          ), // bottom-right
        ];

    for (var i = 0; i < colonyCount; i++) {
      final nest = cornerPositions[i];
      nestPositions.add(nest);

      // Set position in grid's nestPositions list
      grid.nestPositions[i].setFrom(nest);

      // Create rooms for each colony
      _createColonyRooms(grid, nest, i, rng);
    }

    grid.markHomeDistancesDirty();
    return nestPositions;
  }

  /// Create the initial home chamber for a colony.
  void _createColonyRooms(
    WorldGrid grid,
    Vector2 nestCenter,
    int colonyId,
    math.Random rng,
  ) {
    const homeRadius = 4.0;

    // Create home room at nest center
    final homeRoom = Room(
      type: RoomType.home,
      center: nestCenter.clone(),
      radius: homeRadius,
      colonyId: colonyId,
    );
    grid.addRoom(homeRoom);
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
