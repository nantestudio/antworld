import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

import 'simulation_config.dart';

enum CellType { air, dirt, food, rock }

class WorldGrid {
  WorldGrid(this.config)
      : cells = Uint8List(config.cols * config.rows),
        foodPheromones = Float32List(config.cols * config.rows),
        homePheromones = Float32List(config.cols * config.rows),
        dirtHealth = Float32List(config.cols * config.rows),
        nestPosition = Vector2(config.cols / 2, config.rows / 2);

  final SimulationConfig config;
  final Uint8List cells;
  final Float32List foodPheromones;
  final Float32List homePheromones;
  final Vector2 nestPosition;
  final Float32List dirtHealth;
  final Set<int> _foodCells = <int>{};
  int _terrainVersion = 0;

  int get cols => config.cols;
  int get rows => config.rows;
  int get terrainVersion => _terrainVersion;

  void reset() {
    for (var i = 0; i < cells.length; i++) {
      cells[i] = CellType.dirt.index;
      dirtHealth[i] = config.dirtMaxHealth;
      foodPheromones[i] = 0;
      homePheromones[i] = 0;
    }
    _foodCells.clear();
    _terrainVersion++;
  }

  void carveNest() {
    final cx = nestPosition.x.floor();
    final cy = nestPosition.y.floor();
    for (var dx = -config.nestRadius; dx <= config.nestRadius; dx++) {
      for (var dy = -config.nestRadius; dy <= config.nestRadius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (math.sqrt(dx * dx + dy * dy) <= config.nestRadius + 0.5) {
          setCell(nx, ny, CellType.air);
          homePheromones[index(nx, ny)] = 1.0;
        }
      }
    }
  }

  bool isWalkable(double x, double y) {
    final gx = x.floor();
    final gy = y.floor();
    if (!isInsideIndex(gx, gy)) return false;
    return cellTypeAt(gx, gy) != CellType.dirt;
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
    _terrainVersion++;
  }

  void decay(double factor, double threshold) {
    for (var i = 0; i < foodPheromones.length; i++) {
      var f = foodPheromones[i];
      if (f > threshold) {
        f *= factor;
        foodPheromones[i] = f > threshold ? f : 0;
      } else {
        foodPheromones[i] = 0;
      }

      var h = homePheromones[i];
      if (h > threshold) {
        h *= factor;
        homePheromones[i] = h > threshold ? h : 0;
      } else {
        homePheromones[i] = 0;
      }
    }

    final nestIdx = index(nestPosition.x.floor(), nestPosition.y.floor());
    homePheromones[nestIdx] = 1.0;
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
  }) {
    cells.setAll(0, cellsData);
    dirtHealth.setAll(0, dirtHealthData);
    foodPheromones.setAll(0, foodPheromoneData);
    homePheromones.setAll(0, homePheromoneData);
    _rebuildFoodCache();
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
    final idx = index(x, y);
    foodPheromones[idx] = math.min(1.0, foodPheromones[idx] + amount);
  }

  void depositHomePheromone(int x, int y, double amount) {
    final idx = index(x, y);
    homePheromones[idx] = math.min(1.0, homePheromones[idx] + amount);
  }

  double foodPheromoneAt(int x, int y) => foodPheromones[index(x, y)];

  double homePheromoneAt(int x, int y) => homePheromones[index(x, y)];

  void _rebuildFoodCache() {
    _foodCells.clear();
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] == CellType.food.index) {
        _foodCells.add(i);
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
}
