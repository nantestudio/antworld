import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../simulation/ant.dart';
import '../simulation/colony_simulation.dart';
import '../simulation/world_grid.dart';

enum BrushMode { dig, food, rock }

class AntWorldGame extends FlameGame
    with TapCallbacks, SecondaryTapCallbacks, DragCallbacks, KeyboardEvents {
  AntWorldGame(this.simulation)
      : brushMode = ValueNotifier<BrushMode>(BrushMode.dig);

  final ColonySimulation simulation;
  final ValueNotifier<BrushMode> brushMode;

  double _worldScale = 1;
  final Vector2 _worldOffset = Vector2.zero();
  bool _draggingDig = false;
  bool _draggingFood = false;

  final Paint _screenBgPaint = Paint()..color = const Color(0xFF0F0F0F);
  final Paint _dirtPaint = Paint()..color = const Color(0xFF5D4037);
  final Paint _foodPaint = Paint()..color = const Color(0xFF76FF03);
  final Paint _rockPaint = Paint()..color = const Color(0xFF999999);
  final Paint _antPaint = Paint()..color = const Color(0xFFEEEEEE);
  final Paint _antCarryingPaint = Paint()..color = const Color(0xFF76FF03);
  final Paint _nestPaint = Paint()..color = const Color(0xFFD500F9);
  final Paint _foodPheromonePaint = Paint()..color = const Color(0xFF0064FF);
  final Paint _homePheromonePaint = Paint()..color = const Color(0xFF888888);
  Picture? _terrainPicture;
  int _cachedTerrainVersion = -1;

  @override
  void update(double dt) {
    super.update(dt);
    simulation.update(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawRect(Offset.zero & Size(size.x, size.y), _screenBgPaint);
    canvas.save();
    canvas.translate(_worldOffset.x, _worldOffset.y);
    canvas.scale(_worldScale);
    _renderWorld(canvas);
    canvas.restore();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final width = simulation.config.worldWidth;
    final height = simulation.config.worldHeight;
    final scaleX = size.x / width;
    final scaleY = size.y / height;
    _worldScale = math.min(scaleX, scaleY);
    final scaledWidth = width * _worldScale;
    final scaledHeight = height * _worldScale;
    _worldOffset
      ..x = (size.x - scaledWidth) / 2
      ..y = (size.y - scaledHeight) / 2;
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyP) {
      simulation.togglePheromones();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final placeFood = _shouldPlaceFood(event.deviceKind);
    _setDragMode(placeFood);
    _applyBrush(event.canvasPosition, placeFood);
  }

  @override
  void onTapUp(TapUpEvent event) {
    _stopDrag();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _stopDrag();
  }

  @override
  void onSecondaryTapDown(SecondaryTapDownEvent event) {
    _setDragMode(true);
    _applyBrush(event.canvasPosition, true);
  }

  @override
  void onSecondaryTapUp(SecondaryTapUpEvent event) {
    _stopDrag();
  }

  @override
  void onSecondaryTapCancel(SecondaryTapCancelEvent event) {
    _stopDrag();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _applyBrush(event.canvasPosition, _draggingFood);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_draggingFood || _draggingDig) {
      _applyBrush(event.canvasEndPosition, _draggingFood);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _stopDrag();
  }

  void setBrushMode(BrushMode mode) {
    brushMode.value = mode;
  }

  void refreshViewport() {
    onGameResize(size);
    invalidateTerrainLayer();
  }

  void _renderWorld(Canvas canvas) {
    final world = simulation.world;
    final config = simulation.config;
    final cellSize = config.cellSize;

    _ensureTerrainPicture(world, cellSize);
    if (_terrainPicture != null) {
      canvas.drawPicture(_terrainPicture!);
    } else {
      _drawTerrain(canvas, world, cellSize);
    }

    if (simulation.showPheromones) {
      _drawPheromones(canvas, world, cellSize);
    }

    final nest = world.nestPosition;
    final nestOffset = Offset(nest.x * cellSize, nest.y * cellSize);
    canvas.drawCircle(nestOffset, cellSize * 0.75, _nestPaint);

    for (final Ant ant in simulation.ants) {
      final paint = ant.hasFood ? _antCarryingPaint : _antPaint;
      final pos = Offset(ant.position.x * cellSize, ant.position.y * cellSize);
      canvas.drawCircle(pos, cellSize * 0.35, paint);
    }
  }

  void invalidateTerrainLayer() {
    _cachedTerrainVersion = -1;
    _terrainPicture?.dispose();
    _terrainPicture = null;
  }

  void _ensureTerrainPicture(WorldGrid world, double cellSize) {
    if (world.terrainVersion == _cachedTerrainVersion &&
        _terrainPicture != null) {
      return;
    }
    _terrainPicture?.dispose();
    final recorder = PictureRecorder();
    final terrainCanvas = Canvas(recorder);
    _drawTerrain(terrainCanvas, world, cellSize);
    _terrainPicture = recorder.endRecording();
    _cachedTerrainVersion = world.terrainVersion;
  }

  void _drawTerrain(Canvas canvas, WorldGrid world, double cellSize) {
    final cols = world.cols;
    final rows = world.rows;
    for (var x = 0; x < cols; x++) {
      final dx = x * cellSize;
      for (var y = 0; y < rows; y++) {
        final idx = world.index(x, y);
        final cellValue = world.cells[idx];
        if (cellValue == CellType.air.index) {
          continue;
        }
        final dy = y * cellSize;
        final rect = Rect.fromLTWH(dx, dy, cellSize, cellSize);
        if (cellValue == CellType.dirt.index) {
          canvas.drawRect(rect, _dirtPaint);
        } else if (cellValue == CellType.food.index) {
          canvas.drawRect(rect, _foodPaint);
        } else if (cellValue == CellType.rock.index) {
          canvas.drawRect(rect, _rockPaint);
        }
      }
    }
  }

  void _drawPheromones(Canvas canvas, WorldGrid world, double cellSize) {
    final cols = world.cols;
    final rows = world.rows;
    for (var x = 0; x < cols; x++) {
      final dx = x * cellSize;
      for (var y = 0; y < rows; y++) {
        final idx = world.index(x, y);
        if (world.cells[idx] != CellType.air.index) {
          continue;
        }
        final foodStrength = world.foodPheromones[idx];
        final homeStrength = world.homePheromones[idx];
        if (foodStrength <= 0.05 && homeStrength <= 0.05) {
          continue;
        }
        final dy = y * cellSize;
        final rect = Rect.fromLTWH(dx, dy, cellSize, cellSize);
        if (foodStrength >= homeStrength) {
          final alpha = foodStrength.clamp(0, 1).toDouble();
          _foodPheromonePaint.color =
              const Color(0xFF0064FF).withValues(alpha: alpha);
          canvas.drawRect(rect, _foodPheromonePaint);
        } else {
          final alpha = homeStrength.clamp(0, 0.6).toDouble();
          _homePheromonePaint.color =
              const Color(0xFF888888).withValues(alpha: alpha);
          canvas.drawRect(rect, _homePheromonePaint);
        }
      }
    }
  }

  void _applyBrush(Vector2 widgetPosition, bool placeFoodOverride) {
    final cellPosition = _widgetToCell(widgetPosition);
    if (cellPosition == null) return;
    final mode = placeFoodOverride ? BrushMode.food : brushMode.value;
    switch (mode) {
      case BrushMode.food:
        simulation.placeFood(cellPosition);
        break;
      case BrushMode.rock:
        simulation.placeRock(cellPosition);
        break;
      case BrushMode.dig:
        simulation.dig(cellPosition);
        break;
    }
  }

  void _setDragMode(bool placeFood) {
    _draggingFood = placeFood;
    _draggingDig = !placeFood;
  }

  void _stopDrag() {
    _draggingFood = false;
    _draggingDig = false;
  }

  bool _shouldPlaceFood(PointerDeviceKind? kind) {
    if (_isShiftPressed) {
      return true;
    }

    if (kind == PointerDeviceKind.mouse) {
      return brushMode.value == BrushMode.food;
    }

    return brushMode.value == BrushMode.food;
  }

  bool get _isShiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  Vector2? _widgetToCell(Vector2 widgetPosition) {
    final px = (widgetPosition.x - _worldOffset.x) / _worldScale;
    final py = (widgetPosition.y - _worldOffset.y) / _worldScale;
    final width = simulation.config.worldWidth;
    final height = simulation.config.worldHeight;
    if (px < 0 || py < 0 || px >= width || py >= height) {
      return null;
    }
    return Vector2(px / simulation.config.cellSize, py / simulation.config.cellSize);
  }
}
