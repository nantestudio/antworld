import 'dart:collection';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'world_grid.dart';

const _kMinCells = <RoomType, int>{
  RoomType.nursery: 32,
  RoomType.foodStorage: 48,
  RoomType.barracks: 40,
};

const _kMaxCells = <RoomType, int>{
  RoomType.nursery: 180,
  RoomType.foodStorage: 240,
  RoomType.barracks: 200,
};

/// Current state of the HUD painter.
@immutable
class RoomPainterState {
  const RoomPainterState({
    required this.isPainting,
    required this.roomType,
    required this.colonyId,
    required this.cellCount,
    this.errorMessage,
  });

  const RoomPainterState.idle()
    : isPainting = false,
      roomType = null,
      colonyId = 0,
      cellCount = 0,
      errorMessage = null;

  final bool isPainting;
  final RoomType? roomType;
  final int colonyId;
  final int cellCount;
  final String? errorMessage;

  RoomPainterState copyWith({
    bool? isPainting,
    RoomType? roomType,
    int? colonyId,
    int? cellCount,
    String? errorMessage,
  }) {
    return RoomPainterState(
      isPainting: isPainting ?? this.isPainting,
      roomType: roomType ?? this.roomType,
      colonyId: colonyId ?? this.colonyId,
      cellCount: cellCount ?? this.cellCount,
      errorMessage: errorMessage,
    );
  }
}

enum RoomBlueprintStatus {
  pending, // Waiting for builder assignment
  queued, // Added to build queue
  digging, // Builder actively carving
  complete, // Converted to a formal room
  cancelled,
  rejected,
}

/// Arbitrary painted shape describing a future room layout.
class RoomBlueprint {
  RoomBlueprint({
    required this.id,
    required this.colonyId,
    required this.type,
    required this.cells,
    required this.connectionPath,
  }) : center = _centerOf(cells);

  final int id;
  final int colonyId;
  final RoomType type;
  final Set<(int, int)> cells;
  final List<(int, int)> connectionPath;
  final Vector2 center;
  RoomBlueprintStatus status = RoomBlueprintStatus.pending;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'colonyId': colonyId,
      'type': type.index,
      'cells': cells
          .map((cell) => {'x': cell.$1, 'y': cell.$2})
          .toList(growable: false),
      'connection': connectionPath
          .map((cell) => {'x': cell.$1, 'y': cell.$2})
          .toList(growable: false),
      'status': status.index,
    };
  }

  factory RoomBlueprint.fromJson(Map<String, dynamic> json) {
    final cellList = <(int, int)>{};
    final cells = json['cells'];
    if (cells is List) {
      for (final entry in cells) {
        if (entry is Map<String, dynamic>) {
          final x = entry['x'];
          final y = entry['y'];
          if (x is num && y is num) {
            cellList.add((x.toInt(), y.toInt()));
          }
        }
      }
    }
    final connection = <(int, int)>[];
    final connectionData = json['connection'];
    if (connectionData is List) {
      for (final entry in connectionData) {
        if (entry is Map<String, dynamic>) {
          final x = entry['x'];
          final y = entry['y'];
          if (x is num && y is num) {
            connection.add((x.toInt(), y.toInt()));
          }
        }
      }
    }
    final typeIndex = (json['type'] as num?)?.toInt() ?? 0;
    final clampedType =
        RoomType.values[typeIndex.clamp(0, RoomType.values.length - 1)];

    final blueprint = RoomBlueprint(
      id: (json['id'] as num?)?.toInt() ?? 0,
      colonyId: (json['colonyId'] as num?)?.toInt() ?? 0,
      type: clampedType,
      cells: cellList,
      connectionPath: connection,
    );
    final statusIndex = (json['status'] as num?)?.toInt();
    if (statusIndex != null &&
        statusIndex >= 0 &&
        statusIndex < RoomBlueprintStatus.values.length) {
      blueprint.status = RoomBlueprintStatus.values[statusIndex];
    }
    return blueprint;
  }

  double estimateRadius() {
    return math.sqrt(math.max(1, cells.length) / math.pi);
  }

  double buildProgress(WorldGrid world) {
    if (status == RoomBlueprintStatus.complete) {
      return 1.0;
    }
    final totalCells = cells.length + connectionPath.length;
    if (totalCells == 0) return 0;
    var dug = 0;
    for (final cell in cells) {
      if (_isAir(world, cell.$1, cell.$2)) {
        dug++;
      }
    }
    for (final cell in connectionPath) {
      if (_isAir(world, cell.$1, cell.$2)) {
        dug++;
      }
    }
    return dug / totalCells;
  }

  static bool _isAir(WorldGrid world, int x, int y) {
    if (!world.isInsideIndex(x, y)) return false;
    return world.cellTypeAt(x, y) == CellType.air;
  }

  static Vector2 _centerOf(Set<(int, int)> cells) {
    if (cells.isEmpty) return Vector2.zero();
    var sumX = 0.0;
    var sumY = 0.0;
    for (final cell in cells) {
      sumX += cell.$1 + 0.5;
      sumY += cell.$2 + 0.5;
    }
    final inv = 1.0 / cells.length;
    return Vector2(sumX * inv, sumY * inv);
  }
}

class RoomBlueprintResult {
  const RoomBlueprintResult({required this.success, this.blueprint, this.error});

  final bool success;
  final RoomBlueprint? blueprint;
  final String? error;
}

class _PaintingSession {
  _PaintingSession({required this.type, required this.colonyId});

  final RoomType type;
  final int colonyId;
  final Set<(int, int)> cells = <(int, int)>{};
}

/// Tracks blueprint data and HUD painting state.
class RoomBlueprintManager {
  RoomBlueprintManager();
  final List<RoomBlueprint> _blueprints = [];
  final ValueNotifier<RoomPainterState> painterState =
      ValueNotifier<RoomPainterState>(const RoomPainterState.idle());
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  int _nextId = 1;
  _PaintingSession? _session;

  List<RoomBlueprint> get blueprints =>
      List<RoomBlueprint>.unmodifiable(_blueprints);

  bool get isPainting => _session != null;

  Set<(int, int)> get paintingCells =>
      _session?.cells ?? const <(int, int)>{};

  void startPainting(RoomType type, int colonyId) {
    _session = _PaintingSession(type: type, colonyId: colonyId);
    painterState.value = RoomPainterState(
      isPainting: true,
      roomType: type,
      colonyId: colonyId,
      cellCount: 0,
    );
  }

  void cancelPainting() {
    _session = null;
    painterState.value = const RoomPainterState.idle();
  }

  bool addPaintCell(int x, int y, WorldGrid world) {
    final session = _session;
    if (session == null) return false;
    if (!world.isInsideIndex(x, y)) return false;
    if (world.cellTypeAt(x, y) == CellType.rock) {
      return false;
    }
    final dirtType = world.dirtTypeAt(x, y);
    if (dirtType == DirtType.bedrock) {
      return false;
    }
    final added = session.cells.add((x, y));
    if (added) {
      painterState.value = painterState.value.copyWith(
        cellCount: session.cells.length,
        errorMessage: null,
      );
    }
    return added;
  }

  RoomBlueprintResult finishPainting(WorldGrid world) {
    final session = _session;
    if (session == null) {
      return const RoomBlueprintResult(
        success: false,
        error: 'No active blueprint.',
      );
    }
    if (session.cells.isEmpty) {
      const err = 'Paint at least one tile.';
      painterState.value = painterState.value.copyWith(errorMessage: err);
      return const RoomBlueprintResult(success: false, error: err);
    }
    final minCells = _kMinCells[session.type] ?? 24;
    final maxCells = _kMaxCells[session.type] ?? 300;
    if (session.cells.length < minCells) {
      final err =
          'Blueprint too small. Cover at least $minCells tiles.';
      painterState.value = painterState.value.copyWith(errorMessage: err);
      return RoomBlueprintResult(success: false, error: err);
    }
    if (session.cells.length > maxCells) {
      final err = 'Blueprint too large. Limit is $maxCells tiles.';
      painterState.value = painterState.value.copyWith(errorMessage: err);
      return RoomBlueprintResult(success: false, error: err);
    }
    if (_overlapsExisting(world, session)) {
      const err = 'Cannot overlap existing rooms or blueprints.';
      painterState.value = painterState.value.copyWith(errorMessage: err);
      return const RoomBlueprintResult(success: false, error: err);
    }
    final connection = _buildConnection(world, session);
    if (connection == null) {
      const err = 'No diggable path from nest to blueprint.';
      painterState.value = painterState.value.copyWith(errorMessage: err);
      return const RoomBlueprintResult(success: false, error: err);
    }
    final blueprint = RoomBlueprint(
      id: _nextId++,
      colonyId: session.colonyId,
      type: session.type,
      cells: <(int, int)>{...session.cells},
      connectionPath: connection,
    );
    _blueprints.add(blueprint);
    _session = null;
    painterState.value = const RoomPainterState.idle();
    revision.value++;
    return RoomBlueprintResult(success: true, blueprint: blueprint);
  }

  void remove(int blueprintId) {
    _blueprints.removeWhere((bp) => bp.id == blueprintId);
    revision.value++;
  }

  void clear() {
    _blueprints.clear();
    _session = null;
    painterState.value = const RoomPainterState.idle();
    revision.value++;
  }

  void replaceAll(Iterable<RoomBlueprint> blueprints) {
    cancelPainting();
    _blueprints
      ..clear()
      ..addAll(blueprints);
    revision.value++;
  }

  List<(int, int)>? _buildConnection(
    WorldGrid world,
    _PaintingSession session,
  ) {
    if (_touchesAir(world, session.cells)) {
      return <(int, int)>[];
    }
    final start = world.getNestPosition(session.colonyId);
    final sx = start.x.floor();
    final sy = start.y.floor();
    final queue = Queue<(int, int)>();
    final visited = <int>{};
    final parents = <int, int>{};
    queue.add((sx, sy));
    final maxNodes = math.min(world.cols * world.rows, 20000);
    while (queue.isNotEmpty && visited.length < maxNodes) {
      final (cx, cy) = queue.removeFirst();
      if (!world.isInsideIndex(cx, cy)) continue;
      final idx = world.index(cx, cy);
      if (!visited.add(idx)) continue;
      if (session.cells.contains((cx, cy))) {
        return _reconstructPath(
          parents,
          idx,
          world.index(sx, sy),
          world.cols,
        )
            .where((cell) => world.cellTypeAt(cell.$1, cell.$2) != CellType.air)
            .toList();
      }
      for (final dir in const <(int, int)>[
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
      ]) {
        final nx = cx + dir.$1;
        final ny = cy + dir.$2;
        if (!world.isInsideIndex(nx, ny)) continue;
        final neighborIdx = world.index(nx, ny);
        if (visited.contains(neighborIdx)) continue;
        final cellType = world.cellTypeAt(nx, ny);
        if (cellType == CellType.rock ||
            world.dirtTypeAt(nx, ny) == DirtType.bedrock) {
          continue;
        }
        if (!parents.containsKey(neighborIdx)) {
          parents[neighborIdx] = idx;
        }
        queue.add((nx, ny));
      }
    }
    return null;
  }

  static Iterable<(int, int)> _reconstructPath(
    Map<int, int> parents,
    int target,
    int start,
    int cols,
  ) sync* {
    final stack = <(int, int)>[];
    var current = target;
    while (current != start) {
      final parent = parents[current];
      if (parent == null) break;
      final x = current % cols;
      final y = current ~/ cols;
      stack.add((x, y));
      current = parent;
    }
    while (stack.isNotEmpty) {
      yield stack.removeLast();
    }
  }

  bool _overlapsExisting(WorldGrid world, _PaintingSession session) {
    final centerCandidates = session.cells
        .map((cell) => Vector2(cell.$1 + 0.5, cell.$2 + 0.5))
        .toList();
    for (final room in world.rooms) {
      for (final candidate in centerCandidates) {
        if (room.contains(candidate)) {
          return true;
        }
      }
    }
    for (final blueprint in _blueprints) {
      for (final candidate in session.cells) {
        if (blueprint.cells.contains(candidate)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _touchesAir(WorldGrid world, Set<(int, int)> cells) {
    for (final cell in cells) {
      for (final dir in const <(int, int)>[
        (0, 0),
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
      ]) {
        final nx = cell.$1 + dir.$1;
        final ny = cell.$2 + dir.$2;
        if (!world.isInsideIndex(nx, ny)) continue;
        if (world.cellTypeAt(nx, ny) == CellType.air) {
          return true;
        }
      }
    }
    return false;
  }
}
