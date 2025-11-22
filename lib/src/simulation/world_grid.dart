import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

import 'simulation_config.dart';

enum CellType { air, dirt, food, rock }

/// Nest zone types for spatial organization
enum NestZone {
  none,         // Outside nest or unassigned
  general,      // General nest area (outer ring)
  nursery,      // Larva growing area (middle ring)
  queenChamber, // Queen's room (inner core)
  foodStorage,  // Food storage area (future use)
}

class WorldGrid {
  WorldGrid(this.config, {Vector2? nestOverride})
    : cells = Uint8List(config.cols * config.rows),
      zones = Uint8List(config.cols * config.rows),
      foodPheromones = Float32List(config.cols * config.rows),
      homePheromones = Float32List(config.cols * config.rows),
      dirtHealth = Float32List(config.cols * config.rows),
      _homeDistances = Int32List(config.cols * config.rows),
      nestPosition = (nestOverride ?? Vector2(config.cols / 2, config.rows / 2))
          .clone();

  final SimulationConfig config;
  final Uint8List cells;
  final Uint8List zones; // NestZone for each cell
  final Float32List foodPheromones;
  final Float32List homePheromones;
  final Vector2 nestPosition;
  final Float32List dirtHealth;
  final Set<int> _foodCells = <int>{};
  final Set<int> _activePheromoneCells = <int>{};
  late final UnmodifiableSetView<int> _activePheromoneCellsView =
      UnmodifiableSetView(_activePheromoneCells);
  final Int32List _homeDistances;
  bool _homeDistanceDirty = true;
  int _terrainVersion = 0;

  int get cols => config.cols;
  int get rows => config.rows;
  int get terrainVersion => _terrainVersion;
  Iterable<int> get activePheromoneCells => _activePheromoneCellsView;
  int get foodCount => _foodCells.length;

  void reset() {
    for (var i = 0; i < cells.length; i++) {
      cells[i] = CellType.dirt.index;
      zones[i] = NestZone.none.index;
      dirtHealth[i] = config.dirtMaxHealth;
      foodPheromones[i] = 0;
      homePheromones[i] = 0;
    }
    _foodCells.clear();
    _activePheromoneCells.clear();
    _homeDistanceDirty = true;
    _terrainVersion++;
  }

  void carveNest() {
    final cx = nestPosition.x.floor();
    final cy = nestPosition.y.floor();
    final totalRadius = config.nestRadius + 0.5;

    // Zone radii (concentric rings)
    // Queen chamber: innermost 30% of nest
    // Nursery: 30-60% of nest radius
    // General: 60-100% of nest radius
    final queenRadius = totalRadius * 0.3;
    final nurseryRadius = totalRadius * 0.6;

    for (var dx = -config.nestRadius; dx <= config.nestRadius; dx++) {
      for (var dy = -config.nestRadius; dy <= config.nestRadius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;

        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= totalRadius) {
          setCell(nx, ny, CellType.air);
          final idx = index(nx, ny);
          homePheromones[idx] = 1.0;
          _activePheromoneCells.add(idx);

          // Assign zone based on distance from center
          if (dist <= queenRadius) {
            zones[idx] = NestZone.queenChamber.index;
          } else if (dist <= nurseryRadius) {
            zones[idx] = NestZone.nursery.index;
          } else {
            zones[idx] = NestZone.general.index;
          }
        }
      }
    }
  }

  bool isWalkable(double x, double y) {
    final gx = x.floor();
    final gy = y.floor();
    if (!isInsideIndex(gx, gy)) return false;
    return isWalkableCell(gx, gy);
  }

  bool isWalkableCell(int x, int y) {
    if (!isInsideIndex(x, y)) return false;
    final type = cellTypeAt(x, y);
    return type == CellType.air || type == CellType.food;
  }

  bool isInsideIndex(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;

  int index(int x, int y) => y * cols + x;

  CellType cellTypeAt(int x, int y) => CellType.values[cells[index(x, y)]];

  void setCell(int x, int y, CellType type) {
    final idx = index(x, y);
    final previous = cells[idx];
    final incoming = type.index;
    if (previous == incoming) {
      return;
    }
    cells[idx] = incoming;
    if (type == CellType.dirt) {
      dirtHealth[idx] = config.dirtMaxHealth;
    } else {
      dirtHealth[idx] = 0;
    }

    if (type == CellType.food) {
      _foodCells.add(idx);
    } else {
      _foodCells.remove(idx);
    }

    if (type != CellType.air) {
      foodPheromones[idx] = 0;
      homePheromones[idx] = 0;
      _activePheromoneCells.remove(idx);
    }
    _terrainVersion++;
    _homeDistanceDirty = true;
  }

  void decay(double factor, double threshold) {
    if (_activePheromoneCells.isEmpty) {
      final nestIdx = index(nestPosition.x.floor(), nestPosition.y.floor());
      homePheromones[nestIdx] = 1.0;
      _activePheromoneCells.add(nestIdx);
      return;
    }

    final toRemove = <int>[];
    for (final idx in _activePheromoneCells) {
      var f = foodPheromones[idx];
      if (f > threshold) {
        f *= factor;
        foodPheromones[idx] = f > threshold ? f : 0;
      } else {
        foodPheromones[idx] = 0;
      }

      var h = homePheromones[idx];
      if (h > threshold) {
        h *= factor;
        homePheromones[idx] = h > threshold ? h : 0;
      } else {
        homePheromones[idx] = 0;
      }

      if (foodPheromones[idx] == 0 && homePheromones[idx] == 0) {
        toRemove.add(idx);
      }
    }

    for (final idx in toRemove) {
      _activePheromoneCells.remove(idx);
    }

    final nestIdx = index(nestPosition.x.floor(), nestPosition.y.floor());
    homePheromones[nestIdx] = 1.0;
    _activePheromoneCells.add(nestIdx);
  }

  void digCircle(Vector2 cellPos, int radius) {
    final cx = cellPos.x.floor();
    final cy = cellPos.y.floor();
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (dx * dx + dy * dy <= radius * radius) {
          if (cellTypeAt(nx, ny) != CellType.rock) {
            setCell(nx, ny, CellType.air);
          }
        }
      }
    }
  }

  void placeFood(Vector2 cellPos, int radius) {
    final cx = cellPos.x.floor();
    final cy = cellPos.y.floor();
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (dx * dx + dy * dy <= radius * radius) {
          final idx = index(nx, ny);
          if (cells[idx] == CellType.air.index) {
            setCell(nx, ny, CellType.food);
          }
        }
      }
    }
  }

  void placeRock(Vector2 cellPos, int radius) {
    final cx = cellPos.x.floor();
    final cy = cellPos.y.floor();
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (dx * dx + dy * dy <= radius * radius) {
          setCell(nx, ny, CellType.rock);
        }
      }
    }
  }

  void removeFood(int x, int y) {
    final idx = index(x, y);
    if (cells[idx] == CellType.food.index) {
      setCell(x, y, CellType.air);
    }
  }

  void loadState({
    required Uint8List cellsData,
    required Float32List dirtHealthData,
    required Float32List foodPheromoneData,
    required Float32List homePheromoneData,
    Uint8List? zonesData,
  }) {
    cells.setAll(0, cellsData);
    dirtHealth.setAll(0, dirtHealthData);
    foodPheromones.setAll(0, foodPheromoneData);
    homePheromones.setAll(0, homePheromoneData);
    if (zonesData != null && zonesData.length == zones.length) {
      zones.setAll(0, zonesData);
    }
    _rebuildFoodCache();
    _rebuildPheromoneCache();
    _terrainVersion++;
  }

  bool damageDirt(int x, int y, double amount) {
    if (!isInsideIndex(x, y)) return false;
    final idx = index(x, y);
    if (cells[idx] != CellType.dirt.index) {
      return false;
    }
    final newHealth = dirtHealth[idx] - amount;
    if (newHealth > 0) {
      dirtHealth[idx] = newHealth;
      return false;
    }
    setCell(x, y, CellType.air);
    return true;
  }

  void depositFoodPheromone(int x, int y, double amount) {
    if (!isInsideIndex(x, y)) return;
    final idx = index(x, y);
    foodPheromones[idx] = math.min(1.0, foodPheromones[idx] + amount);
    _activePheromoneCells.add(idx);
  }

  void depositHomePheromone(int x, int y, double amount) {
    if (!isInsideIndex(x, y)) return;
    final idx = index(x, y);
    homePheromones[idx] = math.min(1.0, homePheromones[idx] + amount);
    _activePheromoneCells.add(idx);
  }

  double foodPheromoneAt(int x, int y) {
    if (!isInsideIndex(x, y)) return 0;
    return foodPheromones[index(x, y)];
  }

  double homePheromoneAt(int x, int y) {
    if (!isInsideIndex(x, y)) return 0;
    return homePheromones[index(x, y)];
  }

  void _rebuildFoodCache() {
    _foodCells.clear();
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] == CellType.food.index) {
        _foodCells.add(i);
      }
    }
  }

  void _rebuildPheromoneCache() {
    _activePheromoneCells.clear();
    for (var i = 0; i < cells.length; i++) {
      if (foodPheromones[i] > 0 || homePheromones[i] > 0) {
        _activePheromoneCells.add(i);
      }
    }
  }

  Vector2? nearestFood(Vector2 from, double maxDistance) {
    if (_foodCells.isEmpty) {
      return null;
    }
    final maxDistSq = maxDistance * maxDistance;
    var bestDistSq = maxDistSq;
    Vector2? best;
    final fx = from.x;
    final fy = from.y;
    for (final idx in _foodCells) {
      final x = (idx % cols) + 0.5;
      final y = (idx ~/ cols) + 0.5;
      final dx = x - fx;
      final dy = y - fy;
      final distSq = dx * dx + dy * dy;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = Vector2(x, y);
      }
    }
    return best;
  }

  Vector2? directionToNest(Vector2 from) {
    _ensureHomeDistances();
    final gx = from.x.floor();
    final gy = from.y.floor();
    if (!isInsideIndex(gx, gy)) {
      return null;
    }
    final idx = index(gx, gy);
    final current = _homeDistances[idx];
    if (current <= 0) {
      return null;
    }
    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    for (final dir in dirs) {
      final nx = gx + dir[0];
      final ny = gy + dir[1];
      if (!isInsideIndex(nx, ny)) continue;
      final neighborIdx = index(nx, ny);
      final dist = _homeDistances[neighborIdx];
      if (dist >= 0 && dist < current && isWalkableCell(nx, ny)) {
        final center = Vector2(nx + 0.5, ny + 0.5);
        return center - from;
      }
    }
    return null;
  }

  void markHomeDistancesDirty() {
    _homeDistanceDirty = true;
  }

  void _ensureHomeDistances() {
    if (!_homeDistanceDirty) {
      return;
    }
    _homeDistanceDirty = false;
    for (var i = 0; i < _homeDistances.length; i++) {
      _homeDistances[i] = -1;
    }
    final startX = nestPosition.x.floor().clamp(0, cols - 1);
    final startY = nestPosition.y.floor().clamp(0, rows - 1);
    if (!isInsideIndex(startX, startY) || !isWalkableCell(startX, startY)) {
      return;
    }
    final queue = Queue<int>();
    final startIdx = index(startX, startY);
    _homeDistances[startIdx] = 0;
    queue.add(startIdx);
    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final cx = current % cols;
      final cy = current ~/ cols;
      final nextDist = _homeDistances[current] + 1;
      for (final dir in dirs) {
        final nx = cx + dir[0];
        final ny = cy + dir[1];
        if (!isInsideIndex(nx, ny)) continue;
        if (!isWalkableCell(nx, ny)) continue;
        final idx = index(nx, ny);
        if (_homeDistances[idx] != -1) continue;
        _homeDistances[idx] = nextDist;
        queue.add(idx);
      }
    }
  }

  // Zone management methods

  /// Get the zone type at a grid position
  NestZone zoneAt(int x, int y) {
    if (!isInsideIndex(x, y)) return NestZone.none;
    return NestZone.values[zones[index(x, y)]];
  }

  /// Get zone at world position
  NestZone zoneAtPosition(Vector2 pos) {
    return zoneAt(pos.x.floor(), pos.y.floor());
  }

  /// Set zone for a cell
  void setZone(int x, int y, NestZone zone) {
    if (!isInsideIndex(x, y)) return;
    zones[index(x, y)] = zone.index;
  }

  /// Check if position is within a specific zone
  bool isInZone(Vector2 pos, NestZone zone) {
    return zoneAtPosition(pos) == zone;
  }

  /// Find nearest walkable cell of a specific zone type
  Vector2? nearestZoneCell(Vector2 from, NestZone targetZone, double maxDistance) {
    final maxDistSq = maxDistance * maxDistance;
    var bestDistSq = maxDistSq;
    Vector2? best;
    final fx = from.x;
    final fy = from.y;

    // Scan area around the position
    final scanRadius = maxDistance.ceil();
    final cx = fx.floor();
    final cy = fy.floor();

    for (var dx = -scanRadius; dx <= scanRadius; dx++) {
      for (var dy = -scanRadius; dy <= scanRadius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (!isWalkableCell(nx, ny)) continue;

        final idx = index(nx, ny);
        if (NestZone.values[zones[idx]] != targetZone) continue;

        final cellX = nx + 0.5;
        final cellY = ny + 0.5;
        final ddx = cellX - fx;
        final ddy = cellY - fy;
        final distSq = ddx * ddx + ddy * ddy;

        if (distSq < bestDistSq) {
          bestDistSq = distSq;
          best = Vector2(cellX, cellY);
        }
      }
    }
    return best;
  }

  /// Get all cells in a zone (for debugging/visualization)
  List<Vector2> getCellsInZone(NestZone zone) {
    final result = <Vector2>[];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (zoneAt(x, y) == zone) {
          result.add(Vector2(x + 0.5, y + 0.5));
        }
      }
    }
    return result;
  }
}
