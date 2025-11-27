import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

import 'simulation_config.dart';

enum CellType { air, dirt, food, rock }

/// Dirt hardness types - determines HP and dig difficulty
enum DirtType {
  softSand, // 5 HP - very easy to dig
  looseSoil, // 12 HP - easy
  packedEarth, // 25 HP - medium
  clay, // 50 HP - hard
  hardite, // 100 HP - very hard, rare
  bedrock, // 200 HP - extremely hard (replaces rock)
}

/// HP values for each dirt type (halved again for easier digging)
const Map<DirtType, double> dirtTypeHealth = {
  DirtType.softSand: 2.5,
  DirtType.looseSoil: 6.0,
  DirtType.packedEarth: 10.0,
  DirtType.clay: 20.0,
  DirtType.hardite: 40.0,
  DirtType.bedrock: 100.0,
};

/// Nest zone types for spatial organization
enum NestZone {
  none, // Outside nest or unassigned
  general, // General nest area (outer ring)
  nursery, // Larva growing area (middle ring)
  queenChamber, // Queen's room (inner core)
  foodStorage, // Food storage area
  barracks, // Worker/soldier rest area
}

/// Room types for discrete colony chambers
enum RoomType {
  home, // Hatchery / queen's chamber, food delivery point
  nursery, // Egg/larva care area
  foodStorage, // Food stockpile
  barracks, // Worker/soldier rest area
}

/// A discrete room in the colony
class Room {
  Room({
    required this.type,
    required Vector2 center,
    required this.radius,
    required this.colonyId,
    int? maxCapacity,
    this.currentOccupancy = 0,
    this.needsExpansion = false,
  }) : center = center.clone(),
       maxCapacity = maxCapacity ?? defaultCapacity[type] ?? 0;

  final RoomType type;
  final Vector2 center;
  final double radius;
  final int colonyId;
  final int maxCapacity;
  int currentOccupancy;
  bool needsExpansion;
  List<(int, int)>? _perimeterCache;

  static const Map<RoomType, int> defaultCapacity = {
    RoomType.home: 5,
    RoomType.nursery: 20,
    RoomType.foodStorage: 100,
    RoomType.barracks: 15,
  };

  bool get isFull => currentOccupancy >= maxCapacity;
  bool get isOverCapacity => currentOccupancy > (maxCapacity * 1.2).floor();

  /// Check if a position is inside this room
  bool contains(Vector2 pos) => pos.distanceTo(center) <= radius;

  /// Convert to JSON for saving
  Map<String, dynamic> toJson() => {
    'type': type.index,
    'centerX': center.x,
    'centerY': center.y,
    'radius': radius,
    'colonyId': colonyId,
    'maxCapacity': maxCapacity,
    'currentOccupancy': currentOccupancy,
    'needsExpansion': needsExpansion,
  };

  /// Create from JSON for loading
  factory Room.fromJson(Map<String, dynamic> json) {
    final typeIndex = (json['type'] as num?)?.toInt() ?? 0;
    final clampedType =
        RoomType.values[typeIndex.clamp(0, RoomType.values.length - 1)];
    return Room(
      type: clampedType,
      center: Vector2(
        (json['centerX'] as num).toDouble(),
        (json['centerY'] as num).toDouble(),
      ),
      radius: (json['radius'] as num).toDouble(),
      colonyId: (json['colonyId'] as num?)?.toInt() ?? 0,
      maxCapacity: (json['maxCapacity'] as num?)?.toInt(),
      currentOccupancy: (json['currentOccupancy'] as num?)?.toInt() ?? 0,
      needsExpansion: json['needsExpansion'] as bool? ?? false,
    );
  }

  void invalidateCache() => _perimeterCache = null;

  List<(int, int)> perimeter(WorldGrid world) {
    return _perimeterCache ??= _buildPerimeter(world);
  }

  List<(int, int)> _buildPerimeter(WorldGrid world) {
    final result = <(int, int)>[];
    final cx = center.x.floor();
    final cy = center.y.floor();
    final r = radius.ceil() + 2;
    for (var dx = -r; dx <= r; dx++) {
      for (var dy = -r; dy <= r; dy++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!world.isInsideIndex(x, y)) continue;
        final dist = math.sqrt(dx * dx + dy * dy);
        final nearEdge = dist >= radius && dist <= radius + 1.2;
        if (nearEdge) {
          result.add((x, y));
        }
      }
    }
    return result;
  }
}

class WorldGrid {
  WorldGrid(this.config, {Vector2? nestOverride, Vector2? nest1Override})
    : cells = Uint8List(config.cols * config.rows),
      zones = Uint8List(config.cols * config.rows),
      dirtTypes = Uint8List(config.cols * config.rows),
      foodPheromones0 = Float32List(config.cols * config.rows),
      foodPheromones1 = Float32List(config.cols * config.rows),
      foodPheromoneOwner0 = Uint8List(config.cols * config.rows),
      foodPheromoneOwner1 = Uint8List(config.cols * config.rows),
      homePheromones0 = Float32List(config.cols * config.rows),
      homePheromones1 = Float32List(config.cols * config.rows),
      homePheromoneOwner0 = Uint8List(config.cols * config.rows),
      homePheromoneOwner1 = Uint8List(config.cols * config.rows),
      blockedPheromones = Float32List(config.cols * config.rows),
      foodScent = Float32List(config.cols * config.rows),
      _foodScentBuffer = Float32List(config.cols * config.rows),
      dirtHealth = Float32List(config.cols * config.rows),
      foodAmount = Uint8List(config.cols * config.rows),
      _homeDistances0 = Int32List(config.cols * config.rows),
      _homeDistances1 = Int32List(config.cols * config.rows),
      _homeDistances2 = Int32List(config.cols * config.rows),
      _homeDistances3 = Int32List(config.cols * config.rows),
      nestPositions = List.generate(4, (i) {
        if (i == 0) {
          return (nestOverride ?? Vector2(config.cols / 2, config.rows / 2))
              .clone();
        }
        if (i == 1) {
          return (nest1Override ?? Vector2(config.cols / 2, config.rows * 0.2))
              .clone();
        }
        return Vector2.zero(); // Positions 2,3 set by world generator
      });

  // Reduced to slow early snowballing; tuned alongside foodPerNewAnt in SimulationConfig.
  static const int defaultFoodPerCell = 24;

  final SimulationConfig config;
  final Uint8List cells;
  final Uint8List zones; // NestZone for each cell
  final Uint8List dirtTypes; // DirtType for each cell
  // Per-colony pheromone layers - each colony only senses its own trails
  final Float32List foodPheromones0; // Colony 0 food trails
  final Float32List foodPheromones1; // Colony 1 food trails
  final Uint8List foodPheromoneOwner0;
  final Uint8List foodPheromoneOwner1;
  final Float32List homePheromones0; // Colony 0 home trails
  final Float32List homePheromones1; // Colony 1 home trails
  final Uint8List homePheromoneOwner0;
  final Uint8List homePheromoneOwner1;
  final Float32List
  blockedPheromones; // Warning pheromone for dead ends/obstacles (shared)
  final Float32List
  foodScent; // Diffusing scent from food sources (flows through air like gas)
  final Float32List _foodScentBuffer; // Double buffer for diffusion
  final List<Vector2> nestPositions; // All colony nest positions (up to 4)
  final Float32List dirtHealth;
  final Set<int> _reinforcedCells = <int>{};
  late final UnmodifiableSetView<int> _reinforcedCellsView =
      UnmodifiableSetView(_reinforcedCells);
  final Set<int> _activeFoodScentCells = <int>{};
  late final UnmodifiableSetView<int> _activeFoodScentCellsView =
      UnmodifiableSetView(_activeFoodScentCells);

  // Legacy getters for backwards compatibility
  Vector2 get nestPosition => nestPositions[0];
  Vector2 get nest1Position => nestPositions[1];
  final Uint8List foodAmount; // Amount of food in each food cell (0-255)
  final Set<int> _foodCells = <int>{};
  final Set<int> _activePheromoneCells = <int>{};
  late final UnmodifiableSetView<int> _activePheromoneCellsView =
      UnmodifiableSetView(_activePheromoneCells);
  final Int32List _homeDistances0; // BFS distances to colony 0 nest
  final Int32List _homeDistances1; // BFS distances to colony 1 nest
  final Int32List _homeDistances2; // BFS distances to colony 2 nest
  final Int32List _homeDistances3; // BFS distances to colony 3 nest
  bool _homeDistance0Dirty = true;
  bool _homeDistance1Dirty = true;
  bool _homeDistance2Dirty = true;
  bool _homeDistance3Dirty = true;
  int _terrainVersion = 0;
  final List<Room> rooms = []; // Discrete colony chambers

  int get cols => config.cols;
  int get rows => config.rows;
  int get terrainVersion => _terrainVersion;
  Iterable<int> get activePheromoneCells => _activePheromoneCellsView;
  Iterable<int> get foodCells =>
      _foodCells; // Public access for queen food guidance
  int get foodCount => _foodCells.length;
  Iterable<int> get activeFoodScentCells => _activeFoodScentCellsView;
  Iterable<int> get reinforcedCells => _reinforcedCellsView;

  void reset() {
    for (var i = 0; i < cells.length; i++) {
      cells[i] = CellType.dirt.index;
      zones[i] = NestZone.none.index;
      dirtTypes[i] = DirtType.packedEarth.index; // Default to medium hardness
      dirtHealth[i] = dirtTypeHealth[DirtType.packedEarth]!;
      foodAmount[i] = 0;
      foodPheromones0[i] = 0;
      foodPheromones1[i] = 0;
      foodPheromoneOwner0[i] = 0;
      foodPheromoneOwner1[i] = 0;
      homePheromones0[i] = 0;
      homePheromones1[i] = 0;
      homePheromoneOwner0[i] = 0;
      homePheromoneOwner1[i] = 0;
      blockedPheromones[i] = 0;
      foodScent[i] = 0;
      _foodScentBuffer[i] = 0;
    }
    _foodCells.clear();
    _activePheromoneCells.clear();
    rooms.clear();
    _reinforcedCells.clear();
    _activeFoodScentCells.clear();
    _homeDistance0Dirty = true;
    _homeDistance1Dirty = true;
    _homeDistance2Dirty = true;
    _homeDistance3Dirty = true;
    _terrainVersion++;
  }

  /// Get nest position for a specific colony (0-3)
  Vector2 getNestPosition(int colonyId) {
    return nestPositions[colonyId.clamp(0, 3)];
  }

  /// Carve both colony nests
  void carveNest() {
    _carveNestAt(nestPosition, 0);
    _carveNestAt(nest1Position, 1);
  }

  void _carveNestAt(Vector2 position, int colonyId) {
    final cx = position.x.floor();
    final cy = position.y.floor();
    final totalRadius = config.nestRadius + 0.5;

    // Zone radii (concentric rings)
    // Queen chamber: innermost 30% of nest
    // Nursery: 30-60% of nest radius
    // General: 60-100% of nest radius
    final queenRadius = totalRadius * 0.3;
    final nurseryRadius = totalRadius * 0.6;

    // Select correct pheromone layer for this colony
    final homeLayer = colonyId == 0 ? homePheromones0 : homePheromones1;

    for (var dx = -config.nestRadius; dx <= config.nestRadius; dx++) {
      for (var dy = -config.nestRadius; dy <= config.nestRadius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;

        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= totalRadius) {
          setCell(nx, ny, CellType.air);
          final idx = index(nx, ny);
          homeLayer[idx] = 1.0;
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

  DirtType dirtTypeAt(int x, int y) => DirtType.values[dirtTypes[index(x, y)]];

  double dirtMaxHealthAt(int x, int y) {
    final type = DirtType.values[dirtTypes[index(x, y)]];
    return dirtTypeHealth[type]!;
  }

  void setDirtType(int x, int y, DirtType type) {
    final idx = index(x, y);
    dirtTypes[idx] = type.index;
    // Reset health to max for this dirt type
    if (cells[idx] == CellType.dirt.index) {
      dirtHealth[idx] = dirtTypeHealth[type]!;
      if (type == DirtType.hardite || type == DirtType.bedrock) {
        _reinforcedCells.add(idx);
      } else {
        _reinforcedCells.remove(idx);
      }
    }
  }

  void setCell(int x, int y, CellType type, {DirtType? dirtType}) {
    final idx = index(x, y);

    if (type == CellType.air) {
      final zone = NestZone.values[zones[idx]];
      final isProtectedZone =
          zone == NestZone.queenChamber || zone == NestZone.nursery;
      if (isProtectedZone && _isRoomBoundary(x, y)) {
        return; // Prevent breaking walls of critical rooms
      }
    }
    final previous = cells[idx];
    final incoming = type.index;
    if (previous == incoming && type != CellType.dirt) {
      return;
    }
    cells[idx] = incoming;
    if (type == CellType.dirt) {
      final dt = dirtType ?? DirtType.packedEarth;
      dirtTypes[idx] = dt.index;
      dirtHealth[idx] = dirtTypeHealth[dt]!;
      if (dt == DirtType.hardite || dt == DirtType.bedrock) {
        _reinforcedCells.add(idx);
      } else {
        _reinforcedCells.remove(idx);
      }
    } else {
      dirtHealth[idx] = 0;
      _reinforcedCells.remove(idx);
    }

    if (type == CellType.food) {
      _foodCells.add(idx);
    } else {
      _foodCells.remove(idx);
    }

    if (type != CellType.air) {
      foodPheromones0[idx] = 0;
      foodPheromones1[idx] = 0;
      foodPheromoneOwner0[idx] = 0;
      foodPheromoneOwner1[idx] = 0;
      homePheromones0[idx] = 0;
      homePheromones1[idx] = 0;
      homePheromoneOwner0[idx] = 0;
      homePheromoneOwner1[idx] = 0;
      _activePheromoneCells.remove(idx);
    }
    _terrainVersion++;
    _homeDistance0Dirty = true;
    _homeDistance1Dirty = true;
    _homeDistance2Dirty = true;
    _homeDistance3Dirty = true;
  }

  void decay(double factor, double threshold) {
    final nest0Idx = index(nestPosition.x.floor(), nestPosition.y.floor());
    final nest1Idx = index(nest1Position.x.floor(), nest1Position.y.floor());

    if (_activePheromoneCells.isEmpty) {
      homePheromones0[nest0Idx] = 1.0;
      homePheromones1[nest1Idx] = 1.0;
      _activePheromoneCells.add(nest0Idx);
      _activePheromoneCells.add(nest1Idx);
      return;
    }

    final blockedFactor = factor * factor;
    final toRemove = <int>[];

    for (final idx in _activePheromoneCells) {
      var hasAny = false;

      // Decay each array only if it has a value
      var f0 = foodPheromones0[idx];
      if (f0 > 0) {
        f0 *= factor;
        if (f0 > threshold) {
          foodPheromones0[idx] = f0;
          hasAny = true;
        } else {
          foodPheromones0[idx] = 0;
          foodPheromoneOwner0[idx] = 0;
        }
      }

      var f1 = foodPheromones1[idx];
      if (f1 > 0) {
        f1 *= factor;
        if (f1 > threshold) {
          foodPheromones1[idx] = f1;
          hasAny = true;
        } else {
          foodPheromones1[idx] = 0;
          foodPheromoneOwner1[idx] = 0;
        }
      }

      var h0 = homePheromones0[idx];
      if (h0 > 0) {
        h0 *= factor;
        if (h0 > threshold) {
          homePheromones0[idx] = h0;
          hasAny = true;
        } else {
          homePheromones0[idx] = 0;
          homePheromoneOwner0[idx] = 0;
        }
      }

      var h1 = homePheromones1[idx];
      if (h1 > 0) {
        h1 *= factor;
        if (h1 > threshold) {
          homePheromones1[idx] = h1;
          hasAny = true;
        } else {
          homePheromones1[idx] = 0;
          homePheromoneOwner1[idx] = 0;
        }
      }

      var b = blockedPheromones[idx];
      if (b > 0) {
        b *= blockedFactor;
        blockedPheromones[idx] = b > threshold ? b : 0;
        hasAny = hasAny || blockedPheromones[idx] > 0;
      }

      if (!hasAny) {
        toRemove.add(idx);
      }
    }

    for (final idx in toRemove) {
      _activePheromoneCells.remove(idx);
    }

    // Nests always radiate max home pheromone
    homePheromones0[nest0Idx] = 1.0;
    homePheromones1[nest1Idx] = 1.0;
    _activePheromoneCells.add(nest0Idx);
    _activePheromoneCells.add(nest1Idx);
  }

  /// Spread food scent through all connected tunnels using BFS flood-fill.
  /// Scent strength decays based on distance from food source.
  /// This runs periodically (not every frame) for performance.
  int _scentUpdateCounter = 0;

  void diffuseFoodScent() {
    if (_foodCells.isEmpty) return;

    // Only do full recalculation every 10 frames for performance
    _scentUpdateCounter++;
    if (_scentUpdateCounter < 10) return;
    _scentUpdateCounter = 0;

    // Clear all scent
    for (var i = 0; i < foodScent.length; i++) {
      foodScent[i] = 0;
    }

    // BFS from each food cell to flood-fill connected air with scent
    const decayPerStep = 0.97; // Scent decay per cell distance
    const maxDistance = 150; // Maximum spread distance

    final visited = List<bool>.filled(cells.length, false);
    final queue = <(int, double)>[]; // (index, scent strength)

    // Start BFS from all food cells
    for (final foodIdx in _foodCells) {
      foodScent[foodIdx] = 1.0;
      visited[foodIdx] = true;
      queue.add((foodIdx, 1.0));
    }

    // Cardinal directions
    const offsets = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];

    var iterations = 0;
    while (queue.isNotEmpty && iterations < cells.length) {
      iterations++;
      final (idx, strength) = queue.removeAt(0);

      // Stop spreading if scent is too weak
      if (strength < 0.01) continue;

      final x = idx % cols;
      final y = idx ~/ cols;

      // Check neighbors
      for (final offset in offsets) {
        final nx = x + offset[0];
        final ny = y + offset[1];

        if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) {
          continue;
        }

        final nidx = index(nx, ny);
        if (visited[nidx]) {
          continue;
        }

        final cellType = cells[nidx];
        // Only spread through air and food cells
        if (cellType != CellType.air.index && cellType != CellType.food.index) {
          continue;
        }

        visited[nidx] = true;
        final newStrength = cellType == CellType.food.index
            ? 1.0
            : strength * decayPerStep;

        // Keep the stronger scent if already set
        if (newStrength > foodScent[nidx]) {
          foodScent[nidx] = newStrength;
        }

        // Continue spreading if not at max distance
        if (iterations < maxDistance * _foodCells.length) {
          queue.add((nidx, newStrength));
        }
      }
    }

    _activeFoodScentCells.clear();
    for (var i = 0; i < foodScent.length; i++) {
      if (foodScent[i] > 0.01) {
        _activeFoodScentCells.add(i);
      }
    }
  }

  /// Get food scent at a position (0.0-1.0)
  double foodScentAt(int x, int y) {
    if (!isInsideIndex(x, y)) return 0;
    return foodScent[index(x, y)];
  }

  /// Compute shortest walkable path from start to any food cell using BFS.
  /// Returns list of cell indices forming the path (excluding start).
  /// Returns null if no walkable path exists within maxLength.
  List<int>? computePathToFood(int startX, int startY, {int maxLength = 50}) {
    if (_foodCells.isEmpty) return null;
    if (!isInsideIndex(startX, startY)) return null;
    if (!isWalkableCell(startX, startY)) return null;

    // BFS from start position
    final visited = <int, int>{}; // Maps cell index to parent index
    final queue = Queue<int>();
    final startIdx = index(startX, startY);

    // Check if start is already food
    if (cells[startIdx] == CellType.food.index) {
      return [startIdx];
    }

    visited[startIdx] = -1; // -1 means no parent (start)
    queue.add(startIdx);

    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];

    int? foodIdx;
    var steps = 0;

    while (queue.isNotEmpty && steps < maxLength * 10) {
      steps++;
      final current = queue.removeFirst();
      final cx = current % cols;
      final cy = current ~/ cols;

      for (final dir in dirs) {
        final nx = cx + dir[0];
        final ny = cy + dir[1];
        if (!isInsideIndex(nx, ny)) continue;

        final nidx = index(nx, ny);
        if (visited.containsKey(nidx)) continue;
        if (!isWalkableCell(nx, ny)) continue;

        visited[nidx] = current; // Record parent

        // Found food!
        if (cells[nidx] == CellType.food.index) {
          foodIdx = nidx;
          break;
        }

        queue.add(nidx);
      }

      if (foodIdx != null) break;
    }

    // No food found
    if (foodIdx == null) return null;

    // Reconstruct path from food back to start
    final path = <int>[];
    var current = foodIdx;
    while (current != startIdx && visited.containsKey(current)) {
      path.add(current);
      current = visited[current]!;
      if (path.length > maxLength) break; // Safety limit
    }

    // Path is from food to start, reverse to get start to food
    return path.reversed.toList();
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

  void placeFood(Vector2 cellPos, int radius, {int? amount}) {
    final cx = cellPos.x.floor();
    final cy = cellPos.y.floor();
    final foodAmt = amount ?? defaultFoodPerCell;
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (dx * dx + dy * dy <= radius * radius) {
          final idx = index(nx, ny);
          if (cells[idx] == CellType.air.index) {
            setCell(nx, ny, CellType.food);
            foodAmount[idx] = foodAmt.clamp(1, 255);
          } else if (cells[idx] == CellType.food.index) {
            // Refill existing food cell
            foodAmount[idx] = math.min(255, foodAmount[idx] + foodAmt);
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
          // Place bedrock dirt (diggable but very hard) instead of impassable rock
          setCell(nx, ny, CellType.dirt);
          setDirtType(nx, ny, DirtType.bedrock);
        }
      }
    }
  }

  void placeHardite(Vector2 cellPos, int radius) {
    final cx = cellPos.x.floor();
    final cy = cellPos.y.floor();
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (!isInsideIndex(nx, ny)) continue;
        if (dx * dx + dy * dy <= radius * radius) {
          setCell(nx, ny, CellType.dirt, dirtType: DirtType.hardite);
        }
      }
    }
  }

  /// Consume one unit of food from a cell. Returns true if food was consumed.
  /// When food amount reaches 0, the cell becomes air.
  bool consumeFood(int x, int y) {
    final idx = index(x, y);
    if (cells[idx] != CellType.food.index) {
      return false;
    }
    if (foodAmount[idx] > 1) {
      foodAmount[idx]--;
      return true;
    }
    // Last unit of food - remove the cell
    foodAmount[idx] = 0;
    setCell(x, y, CellType.air);
    return true;
  }

  /// Get the amount of food in a cell (0 if not food)
  int getFoodAmount(int x, int y) {
    final idx = index(x, y);
    if (cells[idx] != CellType.food.index) return 0;
    return foodAmount[idx];
  }

  void loadState({
    required Uint8List cellsData,
    required Float32List dirtHealthData,
    Uint8List? dirtTypesData,
    Float32List? foodPheromoneData, // Legacy: single layer
    Float32List? homePheromoneData, // Legacy: single layer
    Float32List? foodPheromone0Data, // New: per-colony
    Float32List? foodPheromone1Data,
    Float32List? homePheromone0Data,
    Float32List? homePheromone1Data,
    Uint8List? zonesData,
    Float32List? blockedPheromoneData,
    Uint8List? foodAmountData,
  }) {
    cells.setAll(0, cellsData);
    dirtHealth.setAll(0, dirtHealthData);

    // Load dirt types or default to packedEarth for legacy saves
    if (dirtTypesData != null && dirtTypesData.length == dirtTypes.length) {
      dirtTypes.setAll(0, dirtTypesData);
    } else {
      // Legacy saves: default all dirt to packedEarth (50 HP behavior)
      for (int i = 0; i < cells.length; i++) {
        if (cells[i] == CellType.dirt.index) {
          dirtTypes[i] = DirtType.packedEarth.index;
        }
      }
    }

    // Support both legacy (single layer) and new (per-colony) formats
    if (foodPheromone0Data != null &&
        foodPheromone0Data.length == foodPheromones0.length) {
      foodPheromones0.setAll(0, foodPheromone0Data);
    } else if (foodPheromoneData != null &&
        foodPheromoneData.length == foodPheromones0.length) {
      // Legacy: copy to colony 0 layer
      foodPheromones0.setAll(0, foodPheromoneData);
    }

    if (foodPheromone1Data != null &&
        foodPheromone1Data.length == foodPheromones1.length) {
      foodPheromones1.setAll(0, foodPheromone1Data);
    }

    if (homePheromone0Data != null &&
        homePheromone0Data.length == homePheromones0.length) {
      homePheromones0.setAll(0, homePheromone0Data);
    } else if (homePheromoneData != null &&
        homePheromoneData.length == homePheromones0.length) {
      // Legacy: copy to colony 0 layer
      homePheromones0.setAll(0, homePheromoneData);
    }

    if (homePheromone1Data != null &&
        homePheromone1Data.length == homePheromones1.length) {
      homePheromones1.setAll(0, homePheromone1Data);
    }

    if (zonesData != null && zonesData.length == zones.length) {
      zones.setAll(0, zonesData);
    }
    if (blockedPheromoneData != null &&
        blockedPheromoneData.length == blockedPheromones.length) {
      blockedPheromones.setAll(0, blockedPheromoneData);
    }
    if (foodAmountData != null && foodAmountData.length == foodAmount.length) {
      foodAmount.setAll(0, foodAmountData);
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

  void depositFoodPheromone(int x, int y, double amount, [int colonyId = 0]) {
    if (!isInsideIndex(x, y)) return;
    final idx = index(x, y);
    if (colonyId == 0) {
      foodPheromones0[idx] = math.min(1.0, foodPheromones0[idx] + amount);
      foodPheromoneOwner0[idx] = colonyId.clamp(0, 255);
    } else {
      foodPheromones1[idx] = math.min(1.0, foodPheromones1[idx] + amount);
      foodPheromoneOwner1[idx] = colonyId.clamp(0, 255);
    }
    _activePheromoneCells.add(idx);
  }

  void depositHomePheromone(int x, int y, double amount, [int colonyId = 0]) {
    if (!isInsideIndex(x, y)) return;
    final idx = index(x, y);
    if (colonyId == 0) {
      homePheromones0[idx] = math.min(1.0, homePheromones0[idx] + amount);
      homePheromoneOwner0[idx] = colonyId.clamp(0, 255);
    } else {
      homePheromones1[idx] = math.min(1.0, homePheromones1[idx] + amount);
      homePheromoneOwner1[idx] = colonyId.clamp(0, 255);
    }
    _activePheromoneCells.add(idx);
  }

  double foodPheromoneAt(int x, int y, [int colonyId = 0]) {
    if (!isInsideIndex(x, y)) return 0;
    final idx = index(x, y);
    return colonyId == 0 ? foodPheromones0[idx] : foodPheromones1[idx];
  }

  double homePheromoneAt(int x, int y, [int colonyId = 0]) {
    if (!isInsideIndex(x, y)) return 0;
    final idx = index(x, y);
    return colonyId == 0 ? homePheromones0[idx] : homePheromones1[idx];
  }

  void depositBlockedPheromone(int x, int y, double amount) {
    if (!isInsideIndex(x, y)) return;
    final idx = index(x, y);
    blockedPheromones[idx] = math.min(1.0, blockedPheromones[idx] + amount);
    _activePheromoneCells.add(idx);
  }

  double blockedPheromoneAt(int x, int y) {
    if (!isInsideIndex(x, y)) return 0;
    return blockedPheromones[index(x, y)];
  }

  void _rebuildFoodCache() {
    _foodCells.clear();
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] == CellType.food.index) {
        _foodCells.add(i);
        // Initialize amount for old saves that didn't track it
        if (foodAmount[i] == 0) {
          foodAmount[i] = defaultFoodPerCell;
        }
      }
    }
  }

  void _rebuildPheromoneCache() {
    _activePheromoneCells.clear();
    for (var i = 0; i < cells.length; i++) {
      if (foodPheromones0[i] > 0 ||
          foodPheromones1[i] > 0 ||
          homePheromones0[i] > 0 ||
          homePheromones1[i] > 0 ||
          blockedPheromones[i] > 0) {
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

  /// Returns direction to the nest using BFS pathfinding.
  Vector2? directionToNest(Vector2 from, {int colonyId = 0}) {
    _ensureHomeDistances(colonyId);
    final distances = _getHomeDistances(colonyId);
    final gx = from.x.floor();
    final gy = from.y.floor();
    if (!isInsideIndex(gx, gy)) {
      return null;
    }
    final idx = index(gx, gy);
    final current = distances[idx];
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
      final dist = distances[neighborIdx];
      if (dist >= 0 && dist < current && isWalkableCell(nx, ny)) {
        final center = Vector2(nx + 0.5, ny + 0.5);
        return center - from;
      }
    }
    return null;
  }

  void markHomeDistancesDirty() {
    _homeDistance0Dirty = true;
    _homeDistance1Dirty = true;
    _homeDistance2Dirty = true;
    _homeDistance3Dirty = true;
  }

  /// Get home distances array for a colony
  Int32List _getHomeDistances(int colonyId) {
    switch (colonyId) {
      case 0:
        return _homeDistances0;
      case 1:
        return _homeDistances1;
      case 2:
        return _homeDistances2;
      case 3:
        return _homeDistances3;
      default:
        return _homeDistances0;
    }
  }

  /// Check if home distances are dirty for a colony
  bool _isHomeDistanceDirty(int colonyId) {
    switch (colonyId) {
      case 0:
        return _homeDistance0Dirty;
      case 1:
        return _homeDistance1Dirty;
      case 2:
        return _homeDistance2Dirty;
      case 3:
        return _homeDistance3Dirty;
      default:
        return true;
    }
  }

  /// Mark home distances as clean for a colony
  void _markHomeDistanceClean(int colonyId) {
    switch (colonyId) {
      case 0:
        _homeDistance0Dirty = false;
        break;
      case 1:
        _homeDistance1Dirty = false;
        break;
      case 2:
        _homeDistance2Dirty = false;
        break;
      case 3:
        _homeDistance3Dirty = false;
        break;
    }
  }

  void _ensureHomeDistances(int colonyId) {
    if (!_isHomeDistanceDirty(colonyId)) {
      return;
    }

    // Mark as clean
    _markHomeDistanceClean(colonyId);

    final distances = _getHomeDistances(colonyId);
    final nestPos = getNestPosition(colonyId);

    for (var i = 0; i < distances.length; i++) {
      distances[i] = -1;
    }
    final startX = nestPos.x.floor().clamp(0, cols - 1);
    final startY = nestPos.y.floor().clamp(0, rows - 1);
    if (!isInsideIndex(startX, startY) || !isWalkableCell(startX, startY)) {
      return;
    }
    final queue = Queue<int>();
    final startIdx = index(startX, startY);
    distances[startIdx] = 0;
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
      final nextDist = distances[current] + 1;
      for (final dir in dirs) {
        final nx = cx + dir[0];
        final ny = cy + dir[1];
        if (!isInsideIndex(nx, ny)) continue;
        if (!isWalkableCell(nx, ny)) continue;
        final idx = index(nx, ny);
        if (distances[idx] != -1) continue;
        distances[idx] = nextDist;
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
  Vector2? nearestZoneCell(
    Vector2 from,
    NestZone targetZone,
    double maxDistance,
  ) {
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

  // Room management methods

  /// Get the room at a position, if any
  Room? getRoomAt(Vector2 pos) {
    for (final room in rooms) {
      if (room.contains(pos)) {
        return room;
      }
    }
    return null;
  }

  /// Get all rooms of a specific type for a colony
  List<Room> getRoomsOfType(RoomType type, int colonyId) {
    return rooms
        .where((r) => r.type == type && r.colonyId == colonyId)
        .toList();
  }

  /// Get the home room for a colony
  Room? getHomeRoom(int colonyId) {
    return rooms.cast<Room?>().firstWhere(
      (r) => r!.type == RoomType.home && r.colonyId == colonyId,
      orElse: () => null,
    );
  }

  /// Get the nursery room for a colony
  Room? getNurseryRoom(int colonyId) {
    return rooms.cast<Room?>().firstWhere(
      (r) => r!.type == RoomType.nursery && r.colonyId == colonyId,
      orElse: () => null,
    );
  }

  /// Get the food storage room for a colony
  Room? getFoodRoom(int colonyId) {
    return rooms.cast<Room?>().firstWhere(
      (r) => r!.type == RoomType.foodStorage && r.colonyId == colonyId,
      orElse: () => null,
    );
  }

  /// Get the first barracks room for a colony
  Room? getBarracksRoom(int colonyId) {
    return rooms.cast<Room?>().firstWhere(
      (r) => r!.type == RoomType.barracks && r.colonyId == colonyId,
      orElse: () => null,
    );
  }

  /// Get all barracks rooms for a colony
  List<Room> getAllBarracks(int colonyId) {
    return rooms
        .where((r) => r.type == RoomType.barracks && r.colonyId == colonyId)
        .toList();
  }

  /// Find a valid location for a new room near existing colony rooms
  Vector2? findNewRoomLocation(int colonyId, RoomType type, double radius) {
    final existingRooms = rooms.where((r) => r.colonyId == colonyId).toList();
    final homeRoom = getHomeRoom(colonyId);
    final anchor =
        (homeRoom ?? (existingRooms.isNotEmpty ? existingRooms.first : null))
            ?.center ??
        getNestPosition(colonyId);
    final queue = Queue<(int, int)>();
    final visited = <int>{};
    queue.add((anchor.x.floor(), anchor.y.floor()));
    final maxDistance = config.nestRadius * 6.0;
    final searchLimit = math.min(cols * rows, 20000);
    const directions = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];

    while (queue.isNotEmpty && visited.length < searchLimit) {
      final node = queue.removeFirst();
      final cx = node.$1;
      final cy = node.$2;
      if (!isInsideIndex(cx, cy)) continue;
      final idx = index(cx, cy);
      if (!visited.add(idx)) continue;

      final candidate = Vector2(cx + 0.5, cy + 0.5);
      if (candidate.distanceTo(anchor) > maxDistance) {
        continue;
      }

      if (_canPlaceRoomAt(candidate, radius, colonyId)) {
        return candidate;
      }

      for (final dir in directions) {
        final nx = cx + dir.$1 * 2;
        final ny = cy + dir.$2 * 2;
        if (!isInsideIndex(nx, ny)) continue;
        queue.add((nx, ny));
      }
    }
    return null;
  }

  /// Reinforced perimeter cells for a room (used by builders)
  List<(int, int)> getRoomPerimeter(Room room) {
    return room.perimeter(this);
  }

  /// Reinforce a dirt cell to a harder type (returns true if reinforced)
  bool reinforceCell(int x, int y) {
    if (!isInsideIndex(x, y)) return false;
    final idx = index(x, y);
    if (cells[idx] != CellType.dirt.index) return false;

    final currentType = DirtType.values[dirtTypes[idx]];
    DirtType? upgrade;
    switch (currentType) {
      case DirtType.softSand:
        upgrade = DirtType.looseSoil;
        break;
      case DirtType.looseSoil:
        upgrade = DirtType.packedEarth;
        break;
      case DirtType.packedEarth:
        upgrade = DirtType.clay;
        break;
      case DirtType.clay:
        upgrade = DirtType.hardite;
        break;
      default:
        return false; // Already max hardness or bedrock
    }
    setDirtType(x, y, upgrade);
    _terrainVersion++; // Invalidate terrain cache
    return true;
  }

  /// Check if position is inside a specific room type for a colony
  bool isInRoomType(Vector2 pos, RoomType type, int colonyId) {
    final room = getRoomAt(pos);
    return room != null && room.type == type && room.colonyId == colonyId;
  }

  /// Add a room and carve out the space
  void addRoom(Room room) {
    rooms.add(room);
    room.invalidateCache();
    // Carve out the room as air
    final cx = room.center.x.floor();
    final cy = room.center.y.floor();
    final r = room.radius.ceil() + 1;
    for (var dx = -r; dx <= r; dx++) {
      for (var dy = -r; dy <= r; dy++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!isInsideIndex(x, y)) continue;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= room.radius) {
          final idx = index(x, y);
          cells[idx] = CellType.air.index;
          // Assign zone based on room type
          switch (room.type) {
            case RoomType.home:
              zones[idx] = NestZone.queenChamber.index;
              break;
            case RoomType.nursery:
              zones[idx] = NestZone.nursery.index;
              break;
            case RoomType.foodStorage:
              zones[idx] = NestZone.foodStorage.index;
              break;
            case RoomType.barracks:
              zones[idx] = NestZone.barracks.index;
              break;
          }
        }
      }
    }
    _terrainVersion++;
  }

  bool _canPlaceRoomAt(Vector2 candidate, double radius, int colonyId) {
    final margin = 4.0;
    if (candidate.x - radius - 1 < margin ||
        candidate.y - radius - 1 < margin ||
        candidate.x + radius + 1 > cols - margin ||
        candidate.y + radius + 1 > rows - margin) {
      return false;
    }

    for (final room in rooms) {
      if (room.colonyId != colonyId) continue;
      final minSpacing = room.radius + radius + 1.5;
      if (candidate.distanceTo(room.center) < minSpacing) {
        return false;
      }
    }

    var diggableCells = 0;
    final cx = candidate.x.floor();
    final cy = candidate.y.floor();
    final checkRadius = radius.ceil() + 1;
    for (var dx = -checkRadius; dx <= checkRadius; dx++) {
      for (var dy = -checkRadius; dy <= checkRadius; dy++) {
        final x = cx + dx;
        final y = cy + dy;
        if (!isInsideIndex(x, y)) {
          return false;
        }
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > radius + 0.8) {
          continue;
        }
        final cell = cellTypeAt(x, y);
        if (cell == CellType.rock) {
          return false;
        }
        if (cell == CellType.dirt) {
          final dirtType = dirtTypeAt(x, y);
          if (dirtType == DirtType.bedrock) {
            return false;
          }
          if (dirtType != DirtType.hardite) {
            diggableCells++;
          }
        } else {
          diggableCells++;
        }
      }
    }
    final area = math.pi * radius * radius;
    return diggableCells >= area * 0.5;
  }

  bool _isRoomBoundary(int x, int y) {
    final point = Vector2(x + 0.5, y + 0.5);
    for (final room in rooms) {
      final dist = point.distanceTo(room.center);
      if ((dist - room.radius).abs() < 1.5) {
        return true;
      }
    }
    return false;
  }

  bool isReinforcedCell(int x, int y) {
    if (!isInsideIndex(x, y)) return false;
    return _reinforcedCells.contains(index(x, y));
  }
}
