import 'package:flame/components.dart';

class BiomeSettings {
  const BiomeSettings({
    this.rockFormations = 12,
    this.caverns = 8,
    this.foodClusters = 3,
    this.minFoodDistanceFactor = 0.2,
    this.hardnessBias = 1.0,
  });

  /// Count of rock formations to attempt.
  final int rockFormations;

  /// Count of small caverns to carve.
  final int caverns;

  /// Number of food clusters to spawn at generation.
  final int foodClusters;

  /// Minimum distance of food from nests as a fraction of map height (0-0.5).
  final double minFoodDistanceFactor;

  /// Multiplier applied to hardness falloff (1.0 = default, >1 harder outer ring).
  final double hardnessBias;

  BiomeSettings copyWith({
    int? rockFormations,
    int? caverns,
    int? foodClusters,
    double? minFoodDistanceFactor,
    double? hardnessBias,
  }) {
    return BiomeSettings(
      rockFormations: rockFormations ?? this.rockFormations,
      caverns: caverns ?? this.caverns,
      foodClusters: foodClusters ?? this.foodClusters,
      minFoodDistanceFactor:
          minFoodDistanceFactor ?? this.minFoodDistanceFactor,
      hardnessBias: hardnessBias ?? this.hardnessBias,
    );
  }
}

class LayoutAnchor {
  const LayoutAnchor({
    required this.position,
    this.type = LayoutAnchorType.tunnelWaypoint,
    this.radius = 2.0,
  });

  final Vector2 position;
  final LayoutAnchorType type;
  final double radius;
}

enum LayoutAnchorType { tunnelWaypoint, cavern, harditeWall }

class LevelLayout {
  const LevelLayout({
    required this.id,
    required this.seed,
    this.cols,
    this.rows,
    this.colonyCount,
    this.biome = const BiomeSettings(),
    this.nestPositions,
    this.foodOverride,
    this.anchors = const <LayoutAnchor>[],
  });

  /// Identifier for campaign/daily tracking.
  final String id;
  final int seed;

  /// Optional overrides for map dimensions and colony count.
  final int? cols;
  final int? rows;
  final int? colonyCount;

  /// Biome knobs used to tweak generator counts and hardness.
  final BiomeSettings biome;

  /// Optional fixed nest positions (must match colony count).
  final List<Vector2>? nestPositions;

  /// Optional fixed food cluster centers.
  final List<Vector2>? foodOverride;

  /// Optional anchor hints (tunnels/caverns/walls) applied before noise steps.
  final List<LayoutAnchor> anchors;

  LevelLayout copyWith({
    int? seed,
    int? cols,
    int? rows,
    int? colonyCount,
    BiomeSettings? biome,
    List<Vector2>? nestPositions,
    List<Vector2>? foodOverride,
    List<LayoutAnchor>? anchors,
  }) {
    return LevelLayout(
      id: id,
      seed: seed ?? this.seed,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      colonyCount: colonyCount ?? this.colonyCount,
      biome: biome ?? this.biome,
      nestPositions: nestPositions ?? this.nestPositions,
      foodOverride: foodOverride ?? this.foodOverride,
      anchors: anchors ?? this.anchors,
    );
  }
}

LevelLayout dailyLayoutForDate(DateTime date, {String idPrefix = 'daily'}) {
  final y = date.year;
  final m = date.month;
  final d = date.day;
  final seed = ((y * 10000) + (m * 100) + d) * 7919;
  return LevelLayout(
    id: '$idPrefix-$y$m$d',
    seed: seed,
    biome: const BiomeSettings(
      rockFormations: 10,
      caverns: 8,
      foodClusters: 3,
      minFoodDistanceFactor: 0.18,
      hardnessBias: 0.95,
    ),
  );
}
