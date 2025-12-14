import 'dart:math' as math;
import 'package:flame/components.dart';
import 'world_grid.dart';

/// Bonus types that rooms can provide
enum RoomBonus {
  maturationSpeed, // Larvae mature faster
  restRecovery, // Energy recovery faster
  foodPreservation, // Food decays slower
  foodGeneration, // Passive food generation
  eggLayingSpeed, // Queen lays eggs faster
}

/// Extended room type including new functional rooms
enum ExtendedRoomType {
  queenChamber, // Queen's main chamber
  nursery, // Egg/larva care
  foodStorage, // Food stockpile
  barracks, // Rest area
  fungusGarden, // Passive food generation
  trashHeap, // Dead ant disposal
}

/// A planned room with oval dimensions
class RoomPlan {
  RoomPlan({
    required this.type,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    required this.rotation,
    required this.colonyId,
  });

  final RoomType type;
  final Vector2 center;
  final double radiusX; // Horizontal radius (wider)
  final double radiusY; // Vertical radius (narrower)
  final double rotation; // Rotation angle in radians
  final int colonyId;

  /// Get all cells that make up this oval room
  Set<(int, int)> getCells() {
    final cells = <(int, int)>{};
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);

    // Bounding box for the rotated ellipse
    final maxRadius = math.max(radiusX, radiusY).ceil() + 1;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
      for (var dx = -maxRadius; dx <= maxRadius; dx++) {
        // Rotate point back to ellipse-aligned coordinates
        final rx = dx * cosR + dy * sinR;
        final ry = -dx * sinR + dy * cosR;

        // Check if inside ellipse: (rx/a)² + (ry/b)² <= 1
        final normalized = (rx * rx) / (radiusX * radiusX) +
            (ry * ry) / (radiusY * radiusY);

        if (normalized <= 1.0) {
          cells.add((center.x.floor() + dx, center.y.floor() + dy));
        }
      }
    }
    return cells;
  }

  /// Get perimeter cells for wall building
  Set<(int, int)> getPerimeterCells() {
    final interior = getCells();
    final perimeter = <(int, int)>{};

    for (final cell in interior) {
      // Check all 8 neighbors
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final neighbor = (cell.$1 + dx, cell.$2 + dy);
          if (!interior.contains(neighbor)) {
            perimeter.add(neighbor);
          }
        }
      }
    }
    return perimeter;
  }
}

/// A planned tunnel connection between rooms
class TunnelPlan {
  TunnelPlan({
    required this.cells,
    required this.width,
    required this.fromRoom,
    required this.toRoom,
  });

  final List<(int, int)> cells;
  final int width; // 1 = service tunnel, 2-3 = highway
  final RoomPlan? fromRoom;
  final RoomPlan? toRoom;

  /// Get all cells including width expansion
  Set<(int, int)> getAllCells() {
    if (width <= 1) return cells.toSet();

    final expanded = <(int, int)>{};
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      expanded.add(cell);

      if (width >= 2) {
        // Calculate perpendicular direction
        Vector2 perpDir;
        if (i < cells.length - 1) {
          final next = cells[i + 1];
          final dir = Vector2(
            (next.$1 - cell.$1).toDouble(),
            (next.$2 - cell.$2).toDouble(),
          );
          perpDir = Vector2(-dir.y, dir.x)..normalize();
        } else if (i > 0) {
          final prev = cells[i - 1];
          final dir = Vector2(
            (cell.$1 - prev.$1).toDouble(),
            (cell.$2 - prev.$2).toDouble(),
          );
          perpDir = Vector2(-dir.y, dir.x)..normalize();
        } else {
          perpDir = Vector2(1, 0);
        }

        // Add cells on both sides
        for (var w = 1; w < width; w++) {
          final offset = (w / 2).ceil();
          if (w % 2 == 1) {
            expanded.add((
              cell.$1 + (perpDir.x * offset).round(),
              cell.$2 + (perpDir.y * offset).round(),
            ));
          } else {
            expanded.add((
              cell.$1 - (perpDir.x * offset).round(),
              cell.$2 - (perpDir.y * offset).round(),
            ));
          }
        }
      }
    }
    return expanded;
  }
}

/// Colony planner that the queen uses to plan colony layout
class ColonyPlanner {
  ColonyPlanner(this._world);

  final WorldGrid _world;

  // Room size configurations
  static const Map<RoomType, (double, double)> _roomSizes = {
    RoomType.home: (5.0, 4.0), // Queen chamber - medium oval
    RoomType.nursery: (6.0, 4.0), // Nursery - wider for eggs/larvae
    RoomType.foodStorage: (5.0, 5.0), // Food storage - more square
    RoomType.barracks: (7.0, 4.0), // Barracks - long narrow for resting
  };

  // Room bonuses
  static const Map<RoomType, Map<RoomBonus, double>> _roomBonuses = {
    RoomType.home: {
      RoomBonus.eggLayingSpeed: 1.2, // 20% faster egg laying
    },
    RoomType.nursery: {
      RoomBonus.maturationSpeed: 1.3, // 30% faster maturation
    },
    RoomType.foodStorage: {
      RoomBonus.foodPreservation: 0.5, // 50% slower decay
    },
    RoomType.barracks: {
      RoomBonus.restRecovery: 2.0, // 2x faster rest
    },
  };

  /// Get bonus multiplier for a room type
  static double getBonus(RoomType type, RoomBonus bonus) {
    return _roomBonuses[type]?[bonus] ?? 1.0;
  }

  /// Determine what room type the colony needs next
  RoomType? determineNeededRoomType(
    int colonyId,
    int eggCount,
    int foodCount,
    int workerCount,
    List<Room> existingRooms,
  ) {
    final hasNursery =
        existingRooms.any((r) => r.type == RoomType.nursery && r.colonyId == colonyId);
    final hasFoodStorage =
        existingRooms.any((r) => r.type == RoomType.foodStorage && r.colonyId == colonyId);
    final hasBarracks =
        existingRooms.any((r) => r.type == RoomType.barracks && r.colonyId == colonyId);

    // Priority 1: Nursery if eggs exist but no nursery
    if (eggCount > 3 && !hasNursery) {
      return RoomType.nursery;
    }

    // Priority 2: Food storage if food > 30 and no storage
    if (foodCount > 30 && !hasFoodStorage) {
      return RoomType.foodStorage;
    }

    // Priority 3: Barracks if workers > 15 and no barracks
    if (workerCount > 15 && !hasBarracks) {
      return RoomType.barracks;
    }

    // Priority 4: Check for overcrowded rooms
    for (final room in existingRooms) {
      if (room.colonyId == colonyId && room.isOverCapacity) {
        return room.type; // Build satellite of same type
      }
    }

    return null;
  }

  /// Plan the next room based on colony state
  RoomPlan? planNextRoom(
    int colonyId,
    List<Room> existingRooms,
    int eggCount,
    int foodCount,
    int workerCount,
  ) {
    final neededType = determineNeededRoomType(
      colonyId,
      eggCount,
      foodCount,
      workerCount,
      existingRooms,
    );

    if (neededType == null) return null;

    // Find home room as anchor
    final homeRoom = existingRooms.firstWhere(
      (r) => r.type == RoomType.home && r.colonyId == colonyId,
      orElse: () => throw StateError('No home room found for colony $colonyId'),
    );

    // Calculate placement direction based on room type
    final direction = _getRoomDirection(neededType, colonyId, homeRoom.center);

    // Find optimal position along that direction
    final sizes = _roomSizes[neededType] ?? (5.0, 4.0);
    final position = _findPositionAlongDirection(
      origin: homeRoom.center,
      direction: direction,
      minDistance: 10.0,
      maxDistance: 25.0,
      radiusX: sizes.$1,
      radiusY: sizes.$2,
      colonyId: colonyId,
      existingRooms: existingRooms,
    );

    if (position == null) return null;

    // Determine oval orientation (perpendicular to tunnel approach)
    final tunnelAngle = math.atan2(
      position.y - homeRoom.center.y,
      position.x - homeRoom.center.x,
    );
    final ovalRotation = tunnelAngle + math.pi / 2;

    return RoomPlan(
      type: neededType,
      center: position,
      radiusX: sizes.$1,
      radiusY: sizes.$2,
      rotation: ovalRotation,
      colonyId: colonyId,
    );
  }

  /// Get direction for room placement based on type
  Vector2 _getRoomDirection(RoomType type, int colonyId, Vector2 homeCenter) {
    // Calculate food centroid
    final foodCentroid = _calculateFoodCentroid(homeCenter);
    final toFood = foodCentroid - homeCenter;
    if (toFood.length > 0.1) {
      toFood.normalize();
    } else {
      toFood.setValues(0, -1); // Default: up (toward surface)
    }

    switch (type) {
      case RoomType.nursery:
        // Opposite of food direction (deeper = safer)
        return -toFood;

      case RoomType.foodStorage:
        // Toward food sources
        return toFood;

      case RoomType.barracks:
        // Perpendicular to food direction (flanking position)
        return Vector2(-toFood.y, toFood.x);

      case RoomType.home:
        // Should already exist
        return Vector2(0, 1);
    }
  }

  /// Calculate weighted centroid of nearby food
  Vector2 _calculateFoodCentroid(Vector2 from) {
    var centroid = Vector2.zero();
    var totalWeight = 0.0;
    const searchRadius = 100;

    final fromX = from.x.floor();
    final fromY = from.y.floor();

    for (var dy = -searchRadius; dy <= searchRadius; dy++) {
      for (var dx = -searchRadius; dx <= searchRadius; dx++) {
        final x = fromX + dx;
        final y = fromY + dy;

        if (!_world.isInsideIndex(x, y)) continue;
        if (_world.cellTypeAt(x, y) != CellType.food) continue;

        final dist = math.sqrt(dx * dx + dy * dy);
        final weight = 1.0 / (dist + 1);
        centroid.x += x * weight;
        centroid.y += y * weight;
        totalWeight += weight;
      }
    }

    if (totalWeight > 0) {
      centroid.scale(1.0 / totalWeight);
      return centroid;
    }

    // No food found - return position above (toward surface)
    return from + Vector2(0, -20);
  }

  /// Find optimal position along a direction
  Vector2? _findPositionAlongDirection({
    required Vector2 origin,
    required Vector2 direction,
    required double minDistance,
    required double maxDistance,
    required double radiusX,
    required double radiusY,
    required int colonyId,
    required List<Room> existingRooms,
  }) {
    Vector2? bestPosition;
    var bestScore = double.negativeInfinity;

    final normalizedDir = direction.normalized();

    for (var dist = minDistance; dist <= maxDistance; dist += 2.0) {
      final candidate = origin + normalizedDir * dist;

      // Skip if outside world bounds
      if (!_world.isInsideIndex(candidate.x.floor(), candidate.y.floor())) {
        continue;
      }

      var score = 0.0;

      // Prefer soft terrain (easier to dig)
      score += _terrainSoftnessScore(candidate, radiusX) * 3;

      // Avoid other rooms
      score -= _roomProximityPenalty(candidate, radiusX, existingRooms) * 5;

      // Check for blocking terrain
      if (_hasBlockingTerrain(candidate, radiusX)) continue;

      // Prefer positions that connect easily to existing air
      score += _connectivityScore(candidate) * 2;

      if (score > bestScore) {
        bestScore = score;
        bestPosition = candidate.clone();
      }
    }

    return bestPosition;
  }

  /// Score terrain softness (easier to dig = higher score)
  double _terrainSoftnessScore(Vector2 center, double radius) {
    var score = 0.0;
    var count = 0;
    final r = radius.ceil();

    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final x = center.x.floor() + dx;
        final y = center.y.floor() + dy;

        if (!_world.isInsideIndex(x, y)) continue;
        if (_world.cellTypeAt(x, y) != CellType.dirt) continue;

        final dirtType = _world.dirtTypeAt(x, y);
        // Higher score for softer terrain
        switch (dirtType) {
          case DirtType.softSand:
            score += 1.0;
          case DirtType.looseSoil:
            score += 0.8;
          case DirtType.packedEarth:
            score += 0.5;
          case DirtType.clay:
            score += 0.2;
          case DirtType.hardite:
            score += 0.0;
          case DirtType.bedrock:
            score -= 1.0;
        }
        count++;
      }
    }

    return count > 0 ? score / count : 0;
  }

  /// Penalty for being too close to other rooms
  double _roomProximityPenalty(
    Vector2 center,
    double radius,
    List<Room> rooms,
  ) {
    var penalty = 0.0;
    final minSpacing = radius + 3; // At least 3 cells between rooms

    for (final room in rooms) {
      final dist = center.distanceTo(room.center);
      final minDist = minSpacing + room.radius;

      if (dist < minDist) {
        penalty += (minDist - dist) / minDist;
      }
    }

    return penalty;
  }

  /// Check if position has blocking terrain (rock/bedrock)
  bool _hasBlockingTerrain(Vector2 center, double radius) {
    final r = radius.ceil();

    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final x = center.x.floor() + dx;
        final y = center.y.floor() + dy;

        if (!_world.isInsideIndex(x, y)) return true;

        final cellType = _world.cellTypeAt(x, y);
        if (cellType == CellType.rock) return true;

        if (cellType == CellType.dirt) {
          final dirtType = _world.dirtTypeAt(x, y);
          if (dirtType == DirtType.bedrock) return true;
        }
      }
    }

    return false;
  }

  /// Score connectivity to existing air/tunnels
  double _connectivityScore(Vector2 center) {
    var score = 0.0;
    const searchRadius = 15;

    for (var dy = -searchRadius; dy <= searchRadius; dy++) {
      for (var dx = -searchRadius; dx <= searchRadius; dx++) {
        final x = center.x.floor() + dx;
        final y = center.y.floor() + dy;

        if (!_world.isInsideIndex(x, y)) continue;

        if (_world.cellTypeAt(x, y) == CellType.air) {
          final dist = math.sqrt(dx * dx + dy * dy);
          score += 1.0 / (dist + 1);
        }
      }
    }

    return score;
  }

  /// Plan a tunnel from one point to another using BFS
  TunnelPlan? planTunnel(
    Vector2 from,
    Vector2 to, {
    int width = 1,
    RoomPlan? fromRoom,
    RoomPlan? toRoom,
  }) {
    final startX = from.x.floor();
    final startY = from.y.floor();
    final endX = to.x.floor();
    final endY = to.y.floor();

    // BFS to find path
    final queue = <(int, int, List<(int, int)>)>[];
    final visited = <(int, int)>{};

    queue.add((startX, startY, [(startX, startY)]));
    visited.add((startX, startY));

    while (queue.isNotEmpty) {
      final (x, y, path) = queue.removeAt(0);

      // Reached destination
      if (x == endX && y == endY) {
        return TunnelPlan(
          cells: path,
          width: width,
          fromRoom: fromRoom,
          toRoom: toRoom,
        );
      }

      // Check neighbors (4-directional for cleaner tunnels)
      for (final (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        final nx = x + dx;
        final ny = y + dy;
        final neighbor = (nx, ny);

        if (visited.contains(neighbor)) continue;
        if (!_world.isInsideIndex(nx, ny)) continue;

        // Skip bedrock
        if (_world.cellTypeAt(nx, ny) == CellType.dirt) {
          if (_world.dirtTypeAt(nx, ny) == DirtType.bedrock) continue;
        }

        visited.add(neighbor);
        queue.add((nx, ny, [...path, neighbor]));
      }

      // Limit search to prevent infinite loops
      if (visited.length > 5000) break;
    }

    return null;
  }

  /// Get cells that should be reinforced (walls) around a room
  Set<(int, int)> getWallCells(RoomPlan plan) {
    final perimeter = plan.getPerimeterCells();
    final walls = <(int, int)>{};

    for (final cell in perimeter) {
      if (!_world.isInsideIndex(cell.$1, cell.$2)) continue;

      final cellType = _world.cellTypeAt(cell.$1, cell.$2);
      // Only reinforce dirt cells (not air, food, or rock)
      if (cellType == CellType.dirt) {
        walls.add(cell);
      }
    }

    return walls;
  }
}
