import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

import 'simulation_config.dart';

enum CellType { air, dirt, food }

class WorldGrid {
  WorldGrid(this.config)
      : cells = Uint8List(config.cols * config.rows),
        foodPheromones = Float32List(config.cols * config.rows),
        homePheromones = Float32List(config.cols * config.rows),
        nestPosition = Vector2(config.cols / 2, config.rows / 2);

  final SimulationConfig config;
  final Uint8List cells;
  final Float32List foodPheromones;
  final Float32List homePheromones;
  final Vector2 nestPosition;

  int get cols => config.cols;
  int get rows => config.rows;

  void reset() {
    cells.fillRange(0, cells.length, CellType.dirt.index);
    foodPheromones.fillRange(0, foodPheromones.length, 0);
    homePheromones.fillRange(0, homePheromones.length, 0);
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
    cells[index(x, y)] = type.index;
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
          setCell(nx, ny, CellType.air);
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
            cells[idx] = CellType.food.index;
          }
        }
      }
    }
  }

  void removeFood(int x, int y) {
    final idx = index(x, y);
    if (cells[idx] == CellType.food.index) {
      cells[idx] = CellType.air.index;
    }
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
}
