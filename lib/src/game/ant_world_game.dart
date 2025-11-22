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
      : brushMode = ValueNotifier<BrushMode>(BrushMode.dig),
        selectedAnt = ValueNotifier<Ant?>(null);

  final ColonySimulation simulation;
  final ValueNotifier<BrushMode> brushMode;
  final ValueNotifier<Ant?> selectedAnt;

  double _worldScale = 1;
  double _baseScale = 1;
  double _zoomFactor = 1;
  final Vector2 _worldOffset = Vector2.zero();
  Vector2 _canvasSize = Vector2.zero();
  bool _draggingDig = false;
  bool _draggingFood = false;
  static const double _antSelectRadius = 2.0; // cells

  final Paint _screenBgPaint = Paint()..color = const Color(0xFF0F0F0F);
  final Paint _dirtPaint = Paint()..color = const Color(0xFF5D4037);
  final Paint _foodPaint = Paint()..color = const Color(0xFF76FF03);
  final Paint _rockPaint = Paint()..color = const Color(0xFF999999);
  // Colony 0 paints (cyan tones)
  final Paint _antPaint = Paint()..color = const Color(0xFF4DD0E1); // Cyan
  final Paint _antCarryingPaint = Paint()..color = const Color(0xFF00E676); // Green (carrying food)
  // Colony 1 paints (orange/red tones)
  final Paint _enemyAntPaint = Paint()..color = const Color(0xFFFF7043); // Orange
  final Paint _colony1CarryingPaint = Paint()..color = const Color(0xFFFFEB3B); // Yellow (carrying food)
  final Paint _nestPaint = Paint()..color = const Color(0xFF4DD0E1); // Cyan (matches colony 0)
  final Paint _nest1Paint = Paint()..color = const Color(0xFFFF7043); // Orange (matches colony 1)
  final Paint _foodPheromonePaint = Paint()..color = const Color(0xFF0064FF);
  final Paint _homePheromonePaint = Paint()..color = const Color(0xFF888888);
  final Paint _selectionPaint = Paint()
    ..color = const Color(0xFFFFFF00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  Picture? _terrainPicture;
  int _cachedTerrainVersion = -1;
  Picture? _pheromonePicture;
  int _pheromoneFrame = 0;

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
    _canvasSize = size.clone();
    _recalculateBaseScale();
    _updateViewport();
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
    // Check if tapped on an ant first
    final cellPos = _widgetToCell(event.canvasPosition);
    if (cellPos != null) {
      final tappedAnt = _findAntNear(cellPos);
      if (tappedAnt != null) {
        selectedAnt.value = tappedAnt;
        return; // Don't apply brush when selecting ant
      }
    }

    // Clear selection when tapping elsewhere
    selectedAnt.value = null;

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
    _zoomFactor = 1.0; // Reset zoom to fit whole map
    _recalculateBaseScale();
    _updateViewport();
    invalidateTerrainLayer();
  }

  void setZoom(double zoom) {
    final clamped = zoom.clamp(0.1, 5.0); // Allow more zoom range for large maps
    if ((_zoomFactor - clamped).abs() < 0.001) {
      return;
    }
    _zoomFactor = clamped;
    _updateViewport();
  }

  double get zoomFactor => _zoomFactor;

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
      _renderPheromonesLayer(canvas, world, cellSize);
    }

    // Render colony 0 nest (cyan)
    final nest0 = world.nestPosition;
    final nest0Offset = Offset(nest0.x * cellSize, nest0.y * cellSize);
    canvas.drawCircle(nest0Offset, cellSize * 0.75, _nestPaint);
    _drawNestLabel(canvas, nest0Offset, 'Colony 0');

    // Render colony 1 nest (orange)
    final nest1 = world.nest1Position;
    final nest1Offset = Offset(nest1.x * cellSize, nest1.y * cellSize);
    canvas.drawCircle(nest1Offset, cellSize * 0.75, _nest1Paint);
    _drawNestLabel(canvas, nest1Offset, 'Colony 1');

    _renderAnts(canvas, cellSize);
  }

  void _drawNestLabel(Canvas canvas, Offset nestOffset, String label) {
    const labelStyle = TextStyle(
      color: Color(0xFFE0FFB3),
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = nestOffset - Offset(painter.width / 2, painter.height + 6);
    painter.paint(canvas, offset);
  }

  void invalidateTerrainLayer() {
    _cachedTerrainVersion = -1;
    _terrainPicture?.dispose();
    _terrainPicture = null;
    invalidatePheromoneLayer();
  }

  void invalidatePheromoneLayer() {
    _pheromonePicture?.dispose();
    _pheromonePicture = null;
    _pheromoneFrame = 0;
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

  void _renderPheromonesLayer(Canvas canvas, WorldGrid world, double cellSize) {
    const cacheInterval = 3;
    if (_pheromonePicture == null || _pheromoneFrame % cacheInterval == 0) {
      _pheromonePicture?.dispose();
      final recorder = PictureRecorder();
      final pictureCanvas = Canvas(recorder);
      _drawPheromones(pictureCanvas, world, cellSize);
      _pheromonePicture = recorder.endRecording();
    }
    if (_pheromonePicture != null) {
      canvas.drawPicture(_pheromonePicture!);
    }
    _pheromoneFrame++;
  }

  void _drawPheromones(Canvas canvas, WorldGrid world, double cellSize) {
    final cols = world.cols;
    // Only iterate over cells with active pheromones (~200 cells instead of 7,500)
    for (final idx in world.activePheromoneCells) {
      if (world.cells[idx] != CellType.air.index) {
        continue;
      }
      final foodStrength = world.foodPheromones[idx];
      final homeStrength = world.homePheromones[idx];
      if (foodStrength <= 0.05 && homeStrength <= 0.05) {
        continue;
      }

      // Convert index back to x, y coordinates
      final x = idx % cols;
      final y = idx ~/ cols;
      final dx = x * cellSize;
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

  void _renderAnts(Canvas canvas, double cellSize) {
    // Colony 0 paths (cyan/green tones)
    final colony0Path = Path();
    final colony0CarryingPath = Path();
    // Colony 1 paths (orange/red tones)
    final colony1Path = Path();
    final colony1CarryingPath = Path();

    var colony0HasContent = false;
    var colony0CarryingHasContent = false;
    var colony1HasContent = false;
    var colony1CarryingHasContent = false;

    final radius = cellSize * 0.35;
    for (final Ant ant in simulation.ants) {
      final rect = Rect.fromCircle(
        center: Offset(ant.position.x * cellSize, ant.position.y * cellSize),
        radius: radius,
      );
      if (ant.colonyId == 0) {
        if (ant.hasFood) {
          colony0CarryingPath.addOval(rect);
          colony0CarryingHasContent = true;
        } else {
          colony0Path.addOval(rect);
          colony0HasContent = true;
        }
      } else {
        if (ant.hasFood) {
          colony1CarryingPath.addOval(rect);
          colony1CarryingHasContent = true;
        } else {
          colony1Path.addOval(rect);
          colony1HasContent = true;
        }
      }
    }

    // Draw colony 0 ants (cyan/green)
    if (colony0HasContent) {
      canvas.drawPath(colony0Path, _antPaint); // Cyan
    }
    if (colony0CarryingHasContent) {
      canvas.drawPath(colony0CarryingPath, _antCarryingPaint); // Bright green
    }
    // Draw colony 1 ants (orange/red)
    if (colony1HasContent) {
      canvas.drawPath(colony1Path, _enemyAntPaint); // Orange/red
    }
    if (colony1CarryingHasContent) {
      canvas.drawPath(colony1CarryingPath, _colony1CarryingPaint); // Yellow
    }

    // Draw selection highlight
    final selected = selectedAnt.value;
    if (selected != null) {
      final selectionRadius = cellSize * 0.6;
      canvas.drawCircle(
        Offset(selected.position.x * cellSize, selected.position.y * cellSize),
        selectionRadius,
        _selectionPaint,
      );
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

  void _recalculateBaseScale() {
    if (_canvasSize.x == 0 || _canvasSize.y == 0) {
      _baseScale = 1;
      return;
    }
    final width = simulation.config.worldWidth;
    final height = simulation.config.worldHeight;
    final scaleX = _canvasSize.x / width;
    final scaleY = _canvasSize.y / height;
    _baseScale = math.min(scaleX, scaleY);
  }

  void _updateViewport() {
    if (_canvasSize.x == 0 || _canvasSize.y == 0) {
      return;
    }
    final width = simulation.config.worldWidth;
    final height = simulation.config.worldHeight;
    _worldScale = _baseScale * _zoomFactor;
    final scaledWidth = width * _worldScale;
    final scaledHeight = height * _worldScale;
    _worldOffset
      ..x = (_canvasSize.x - scaledWidth) / 2
      ..y = (_canvasSize.y - scaledHeight) / 2;
  }

  Ant? _findAntNear(Vector2 cellPos) {
    Ant? closest;
    double closestDistSq = _antSelectRadius * _antSelectRadius;

    // Check all ants (from all colonies)
    for (final ant in simulation.ants) {
      final distSq = ant.position.distanceToSquared(cellPos);
      if (distSq < closestDistSq) {
        closestDistSq = distSq;
        closest = ant;
      }
    }

    return closest;
  }

  void clearSelection() {
    selectedAnt.value = null;
  }
}
