import 'dart:math' as math;
import 'package:flame/components.dart';
import 'world_grid.dart';

/// A planned expansion that includes both a tunnel and a room at the end
class ExpandColonyPlan {
  ExpandColonyPlan({
    required this.tunnelCells,
    required this.tunnelWidth,
    required this.roomCenter,
    required this.roomRadiusX,
    required this.roomRadiusY,
    required this.roomRotation,
    required this.roomType,
    required this.branchPoint,
    required this.colonyId,
  });

  final List<(int, int)> tunnelCells;
  final int tunnelWidth;
  final Vector2 roomCenter;
  final double roomRadiusX;
  final double roomRadiusY;
  final double roomRotation;
  final RoomType roomType;
  final Vector2 branchPoint;
  final int colonyId;

  /// Get all cells that need to be dug for the room
  Set<(int, int)> getRoomCells() {
    final cells = <(int, int)>{};
    final cosR = math.cos(roomRotation);
    final sinR = math.sin(roomRotation);
    final maxRadius = math.max(roomRadiusX, roomRadiusY).ceil() + 1;
    final cx = roomCenter.x.floor();
    final cy = roomCenter.y.floor();

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
      for (var dx = -maxRadius; dx <= maxRadius; dx++) {
        final rx = dx * cosR + dy * sinR;
        final ry = -dx * sinR + dy * cosR;
        final normalized = (rx * rx) / (roomRadiusX * roomRadiusX) +
            (ry * ry) / (roomRadiusY * roomRadiusY);
        if (normalized <= 1.0) {
          cells.add((cx + dx, cy + dy));
        }
      }
    }
    return cells;
  }

  /// Get wall cells around the room
  Set<(int, int)> getWallCells() {
    final interior = getRoomCells();
    final walls = <(int, int)>{};
    for (final cell in interior) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final neighbor = (cell.$1 + dx, cell.$2 + dy);
          if (!interior.contains(neighbor)) {
            walls.add(neighbor);
          }
        }
      }
    }
    return walls;
  }
}

/// Room size configurations
const Map<RoomType, (double, double)> roomSizes = {
  RoomType.home: (6.0, 4.0),
  RoomType.nursery: (7.0, 5.0),
  RoomType.foodStorage: (5.0, 5.0),
  RoomType.barracks: (8.0, 4.0),
};

/// Tunnel lengths for different room types
const Map<RoomType, (int, int)> tunnelLengths = {
  RoomType.nursery: (10, 15),
  RoomType.foodStorage: (8, 12),
  RoomType.barracks: (8, 12),
};

/// Colony planner that creates tunnel + room expansion plans
class ColonyPlanner {
  ColonyPlanner(this._world);

  final WorldGrid _world;

  /// Determine what room type the colony needs next
  RoomType? determineNeededRoomType(
    int colonyId,
    int eggCount,
    int foodCount,
    int workerCount,
    List<Room> existingRooms,
  ) {
    final colonyRooms = existingRooms.where((r) => r.colonyId == colonyId);
    final hasNursery = colonyRooms.any((r) => r.type == RoomType.nursery);
    final hasFoodStorage = colonyRooms.any((r) => r.type == RoomType.foodStorage);
    final hasBarracks = colonyRooms.any((r) => r.type == RoomType.barracks);

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

    // Priority 4: Check for overcrowded rooms (except home - only one per colony)
    for (final room in colonyRooms) {
      if (room.type != RoomType.home && room.isOverCapacity) {
        return room.type;
      }
    }

    return null;
  }

  /// Plan the next expansion (tunnel + room) for a colony
  ExpandColonyPlan? planExpansion(
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

    if (neededType == null) {
      return null;
    }

    // Find best branch point on existing tunnel network
    final branchPoint = _findBestBranchPoint(colonyId, neededType, existingRooms);
    if (branchPoint == null) {
      return null;
    }

    // Calculate direction for new tunnel
    final direction = _calculateBranchDirection(branchPoint, neededType, colonyId, existingRooms);

    // Determine tunnel length
    final lengths = tunnelLengths[neededType] ?? (10, 15);
    final rng = math.Random();
    final tunnelLength = lengths.$1 + rng.nextInt(lengths.$2 - lengths.$1 + 1);

    // Generate tunnel cells
    final tunnelCells = _generateTunnelCells(branchPoint, direction, tunnelLength);
    if (tunnelCells.isEmpty) return null;

    // Calculate room position at end of tunnel
    final lastCell = tunnelCells.last;
    final roomCenter = Vector2(
      lastCell.$1.toDouble() + direction.x * 2,
      lastCell.$2.toDouble() + direction.y * 2,
    );

    // Room rotation perpendicular to tunnel
    final tunnelAngle = math.atan2(direction.y, direction.x);
    final roomRotation = tunnelAngle + math.pi / 2;

    // Get room size
    final sizes = roomSizes[neededType] ?? (5.0, 4.0);

    // Verify room position is valid
    if (!_canPlaceRoom(roomCenter, sizes.$1, sizes.$2, roomRotation, colonyId, existingRooms)) {
      return null;
    }

    return ExpandColonyPlan(
      tunnelCells: tunnelCells,
      tunnelWidth: 1, // Service tunnel
      roomCenter: roomCenter,
      roomRadiusX: sizes.$1,
      roomRadiusY: sizes.$2,
      roomRotation: roomRotation,
      roomType: neededType,
      branchPoint: branchPoint,
      colonyId: colonyId,
    );
  }

  /// Find the best point to branch a new tunnel from
  Vector2? _findBestBranchPoint(int colonyId, RoomType targetType, List<Room> existingRooms) {
    final tunnels = _world.getTunnelsForColony(colonyId);
    if (tunnels.isEmpty) {
      // No tunnels - branch from home room center
      final home = existingRooms.firstWhere(
        (r) => r.type == RoomType.home && r.colonyId == colonyId,
        orElse: () => throw StateError('No home room for colony $colonyId'),
      );
      return home.center.clone();
    }

    double bestScore = double.negativeInfinity;
    (int, int)? bestCell;

    for (final tunnel in tunnels) {
      for (final cell in tunnel.cells) {
        double score = 0;

        // 1. Distance from existing rooms (more distance = better)
        final minRoomDist = _minDistanceToAnyRoom(cell, colonyId, existingRooms);
        score += minRoomDist * 2.0;

        // 2. Depth preference based on room type
        final depthScore = _depthScore(cell);
        if (targetType == RoomType.nursery) {
          score += depthScore * 1.5; // Deeper is better for nursery
        } else if (targetType == RoomType.foodStorage) {
          score -= depthScore * 1.0; // Shallower for food
        }

        // 3. Penalty for being too close to existing branches
        final branchDensity = _branchDensity(cell, colonyId);
        score -= branchDensity * 3.0;

        // 4. Prefer cells not at the start or end of tunnels
        final tunnelIndex = tunnel.cells.indexOf(cell);
        final midBonus = (tunnelIndex > 2 && tunnelIndex < tunnel.cells.length - 2) ? 2.0 : 0.0;
        score += midBonus;

        if (score > bestScore) {
          bestScore = score;
          bestCell = cell;
        }
      }
    }

    return bestCell != null ? Vector2(bestCell.$1.toDouble(), bestCell.$2.toDouble()) : null;
  }

  /// Calculate direction for a new branch tunnel
  Vector2 _calculateBranchDirection(
    Vector2 branchPoint,
    RoomType targetType,
    int colonyId,
    List<Room> existingRooms,
  ) {
    final home = existingRooms.firstWhere(
      (r) => r.type == RoomType.home && r.colonyId == colonyId,
      orElse: () => throw StateError('No home room for colony $colonyId'),
    );

    // Base direction: away from home
    final awayFromHome = branchPoint - home.center;
    if (awayFromHome.length > 0.1) {
      awayFromHome.normalize();
    } else {
      awayFromHome.setValues(1, 0);
    }

    // Rotate based on room type for variety
    final rng = math.Random();
    double rotationAngle;
    switch (targetType) {
      case RoomType.nursery:
        // Nursery: Continue deeper (small rotation)
        rotationAngle = (rng.nextDouble() - 0.5) * 0.5;
        break;
      case RoomType.foodStorage:
        // Food storage: Perpendicular to main direction
        rotationAngle = (rng.nextBool() ? 1 : -1) * (math.pi / 2 + (rng.nextDouble() - 0.5) * 0.5);
        break;
      case RoomType.barracks:
        // Barracks: Other perpendicular
        rotationAngle = (rng.nextBool() ? 1 : -1) * (math.pi / 2 + (rng.nextDouble() - 0.5) * 0.5);
        break;
      case RoomType.home:
        rotationAngle = 0;
    }

    final cos = math.cos(rotationAngle);
    final sin = math.sin(rotationAngle);
    return Vector2(
      awayFromHome.x * cos - awayFromHome.y * sin,
      awayFromHome.x * sin + awayFromHome.y * cos,
    );
  }

  /// Generate cells for a tunnel path
  List<(int, int)> _generateTunnelCells(Vector2 start, Vector2 direction, int length) {
    final cells = <(int, int)>[];
    final rng = math.Random();

    var currentX = start.x;
    var currentY = start.y;

    for (var i = 0; i < length; i++) {
      // Add organic wobble
      final wobbleX = (rng.nextDouble() - 0.5) * 0.3;
      final wobbleY = (rng.nextDouble() - 0.5) * 0.3;

      currentX += direction.x + wobbleX;
      currentY += direction.y + wobbleY;

      final cellX = currentX.floor();
      final cellY = currentY.floor();

      if (!_world.isInsideIndex(cellX, cellY)) break;
      if (_world.cellTypeAt(cellX, cellY) == CellType.rock) break;

      cells.add((cellX, cellY));
    }

    return cells;
  }

  /// Check if a room can be placed at a position
  bool _canPlaceRoom(
    Vector2 center,
    double radiusX,
    double radiusY,
    double rotation,
    int colonyId,
    List<Room> existingRooms,
  ) {
    final cx = center.x.floor();
    final cy = center.y.floor();
    final maxRadius = math.max(radiusX, radiusY).ceil();

    // Check bounds
    if (cx - maxRadius < 5 || cy - maxRadius < 5 ||
        cx + maxRadius > _world.cols - 5 || cy + maxRadius > _world.rows - 5) {
      return false;
    }

    // Check not overlapping other rooms
    for (final room in existingRooms) {
      if (room.colonyId != colonyId) continue;
      final dist = (room.center - center).length;
      final minDist = math.max(room.radiusX, room.radiusY) + maxRadius + 2;
      if (dist < minDist) {
        return false;
      }
    }

    // Check no rock in the way
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
      for (var dx = -maxRadius; dx <= maxRadius; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!_world.isInsideIndex(x, y)) continue;
        if (_world.cellTypeAt(x, y) == CellType.rock) {
          return false;
        }
      }
    }

    return true;
  }

  /// Calculate minimum distance from a cell to any room
  double _minDistanceToAnyRoom((int, int) cell, int colonyId, List<Room> rooms) {
    double minDist = double.infinity;
    for (final room in rooms) {
      if (room.colonyId != colonyId) continue;
      final dist = math.sqrt(
        math.pow(cell.$1 - room.center.x, 2) +
        math.pow(cell.$2 - room.center.y, 2),
      );
      if (dist < minDist) {
        minDist = dist;
      }
    }
    return minDist;
  }

  /// Calculate depth score (distance from map edge)
  double _depthScore((int, int) cell) {
    final distFromEdge = math.min(
      math.min(cell.$1, _world.cols - cell.$1),
      math.min(cell.$2, _world.rows - cell.$2),
    );
    return distFromEdge.toDouble();
  }

  /// Calculate branch density near a cell
  double _branchDensity((int, int) cell, int colonyId) {
    int branchCount = 0;
    final tunnels = _world.getTunnelsForColony(colonyId);
    for (final tunnel in tunnels) {
      for (final c in tunnel.cells) {
        final dist = math.sqrt(
          math.pow(c.$1 - cell.$1, 2) + math.pow(c.$2 - cell.$2, 2),
        );
        if (dist < 5) {
          branchCount++;
        }
      }
    }
    return branchCount.toDouble();
  }

  /// Legacy compatibility: Plan next room (returns expansion plan as RoomPlan-like data)
  ExpandColonyPlan? planNextRoom(
    int colonyId,
    List<Room> existingRooms,
    int eggCount,
    int foodCount,
    int workerCount,
  ) {
    return planExpansion(colonyId, existingRooms, eggCount, foodCount, workerCount);
  }
}
