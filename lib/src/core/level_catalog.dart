import 'package:flame/components.dart';

import '../simulation/level_layout.dart';

final Map<String, LevelLayout> campaignLayouts = {
  'trailhead': LevelLayout(
    id: 'trailhead',
    seed: 101001,
    cols: 90,
    rows: 70,
    colonyCount: 1,
    biome: const BiomeSettings(
      rockFormations: 8,
      caverns: 6,
      foodClusters: 2,
      minFoodDistanceFactor: 0.3,
      hardnessBias: 1.05,
    ),
    anchors: [
      LayoutAnchor(
        position: Vector2(30, 35),
        type: LayoutAnchorType.cavern,
        radius: 4,
      ),
      LayoutAnchor(
        position: Vector2(65, 20),
        type: LayoutAnchorType.tunnelWaypoint,
        radius: 2,
      ),
    ],
  ),
  'canyon': LevelLayout(
    id: 'canyon',
    seed: 202155,
    cols: 140,
    rows: 100,
    colonyCount: 1,
    biome: const BiomeSettings(
      rockFormations: 16,
      caverns: 5,
      foodClusters: 3,
      minFoodDistanceFactor: 0.25,
      hardnessBias: 1.2,
    ),
    anchors: [
      LayoutAnchor(
        position: Vector2(70, 20),
        type: LayoutAnchorType.harditeWall,
        radius: 6,
      ),
      LayoutAnchor(
        position: Vector2(70, 80),
        type: LayoutAnchorType.harditeWall,
        radius: 6,
      ),
      LayoutAnchor(
        position: Vector2(70, 50),
        type: LayoutAnchorType.cavern,
        radius: 5,
      ),
    ],
  ),
  'sprawl': LevelLayout(
    id: 'sprawl',
    seed: 303221,
    cols: 180,
    rows: 140,
    colonyCount: 1,
    biome: const BiomeSettings(
      rockFormations: 10,
      caverns: 12,
      foodClusters: 4,
      minFoodDistanceFactor: 0.2,
      hardnessBias: 1.0,
    ),
    anchors: [
      LayoutAnchor(
        position: Vector2(90, 40),
        type: LayoutAnchorType.cavern,
        radius: 6,
      ),
      LayoutAnchor(
        position: Vector2(140, 110),
        type: LayoutAnchorType.tunnelWaypoint,
        radius: 3,
      ),
      LayoutAnchor(
        position: Vector2(40, 90),
        type: LayoutAnchorType.tunnelWaypoint,
        radius: 3,
      ),
    ],
  ),
};

LevelLayout? campaignLayoutById(String id) => campaignLayouts[id];
class LevelInfo {
  const LevelInfo({required this.id, required this.title, required this.summary});

  final String id;
  final String title;
  final String summary;
}

const Map<String, LevelInfo> campaignLevelInfo = {
  'trailhead': LevelInfo(
    id: 'trailhead',
    title: 'Trailhead',
    summary: 'Starter map with gentle hardness and spaced-out food.',
  ),
  'canyon': LevelInfo(
    id: 'canyon',
    title: 'Canyon Pass',
    summary: 'Two hardite walls create chokepoints for defense.',
  ),
  'sprawl': LevelInfo(
    id: 'sprawl',
    title: 'Sprawl',
    summary: 'Wide-open tunnels with extra caverns and distant food.',
  ),
};
