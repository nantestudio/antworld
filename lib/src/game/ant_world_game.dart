import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../simulation/ant.dart';
import '../simulation/colony_simulation.dart';
import '../simulation/world_grid.dart';
import '../visuals/ant_sprite.dart';

enum BrushMode { dig, food, rock }

class AntWorldGame extends FlameGame
    with TapCallbacks, SecondaryTapCallbacks, DragCallbacks, KeyboardEvents {
  AntWorldGame(this.simulation)
    : brushMode = ValueNotifier<BrushMode>(BrushMode.dig),
      selectedAnt = ValueNotifier<Ant?>(null);

  final ColonySimulation simulation;
  final ValueNotifier<BrushMode> brushMode;
  final ValueNotifier<Ant?> selectedAnt;
  final ValueNotifier<bool> editMode = ValueNotifier<bool>(
    false,
  ); // Default: navigation mode
  final FrameTelemetry _frameTelemetry = FrameTelemetry();

  double _worldScale = 1;
  double _baseScale = 1;
  double _zoomFactor = 1;
  final Vector2 _worldOffset = Vector2.zero();
  final Vector2 _panOffset = Vector2.zero(); // User pan offset
  Vector2 _canvasSize = Vector2.zero();
  bool _draggingDig = false;
  bool _draggingFood = false;
  static const double _antSelectRadius = 2.0; // cells

  // Pinch zoom / pan state (called from Flutter widget)
  double _scaleStartZoom = 1;
  final Vector2 _scaleStartPan = Vector2.zero();

  final Paint _screenBgPaint = Paint()..color = const Color(0xFF0F0F0F);
  // 5 dirt type paints (from soft sand to hardite)
  final Paint _softSandPaint = Paint()
    ..color = const Color(0xFFD7CCC8); // Light tan
  final Paint _looseSoilPaint = Paint()
    ..color = const Color(0xFFA1887F); // Sandy brown
  final Paint _packedEarthPaint = Paint()
    ..color = const Color(0xFF795548); // Medium brown
  final Paint _clayPaint = Paint()
    ..color = const Color(0xFF5D4037); // Dark brown
  final Paint _harditePaint = Paint()
    ..color = const Color(0xFF8D6E63); // Reddish-brown
  final Paint _bedrockPaint = Paint()
    ..color = const Color(0xFF616161); // Dark gray (replaces rock)
  final Paint _foodPaint = Paint()..color = const Color(0xFF76FF03);
  final Paint _rockPaint = Paint()..color = const Color(0xFF999999);
  // Nest paints for all 4 colonies (match ant colors)
  final Paint _nestPaint = Paint()
    ..color = const Color(0xFFF44336); // Red (matches colony 0)
  final Paint _nest1Paint = Paint()
    ..color = const Color(0xFFFFEB3B); // Yellow (matches colony 1)
  final Paint _nest2Paint = Paint()
    ..color = const Color(0xFF2196F3); // Blue (matches colony 2)
  final Paint _nest3Paint = Paint()
    ..color = const Color(0xFFFFFFFF); // White (matches colony 3)
  // Food scent visualization paint
  final Paint _foodScentPaint = Paint()
    ..color = const Color(0xFF00FF00); // Green for food smell
  // Colony 0 pheromone paints (blue/gray)
  final Paint _foodPheromone0Paint = Paint()..color = const Color(0xFF0064FF);
  final Paint _homePheromone0Paint = Paint()..color = const Color(0xFF888888);
  // Colony 1 pheromone paints (orange/purple)
  final Paint _foodPheromone1Paint = Paint()..color = const Color(0xFFFF6400);
  final Paint _homePheromone1Paint = Paint()..color = const Color(0xFF884488);
  final Paint _selectionPaint = Paint()
    ..color = const Color(0xFFFFFF00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  // Queen paints (larger, with aura) - match colony colors
  final Paint _queen0Paint = Paint()
    ..color = const Color(0xFFD32F2F); // Darker red
  final Paint _queen1Paint = Paint()
    ..color = const Color(0xFFFBC02D); // Darker yellow
  final Paint _queen2Paint = Paint()
    ..color = const Color(0xFF1976D2); // Darker blue
  final Paint _queen3Paint = Paint()
    ..color = const Color(0xFFE0E0E0); // Light gray (white queen)
  final Paint _queenAura0Paint = Paint()
    ..color = const Color(0x33F44336); // Transparent red
  final Paint _queenAura1Paint = Paint()
    ..color = const Color(0x33FFEB3B); // Transparent yellow
  final Paint _queenAura2Paint = Paint()
    ..color = const Color(0x332196F3); // Transparent blue
  final Paint _queenAura3Paint = Paint()
    ..color = const Color(0x33FFFFFF); // Transparent white
  // Larva paint (smaller, lighter)
  final Paint _larva0Paint = Paint()
    ..color = const Color(0x99EF9A9A); // Light red, semi-transparent
  final Paint _larva1Paint = Paint()
    ..color = const Color(0x99FFF59D); // Light yellow, semi-transparent
  final Paint _larva2Paint = Paint()
    ..color = const Color(0x9990CAF9); // Light blue, semi-transparent
  final Paint _larva3Paint = Paint()
    ..color = const Color(0x99E0E0E0); // Light gray, semi-transparent
  // Egg paint (tiny, colony-colored)
  final Paint _egg0Paint = Paint()
    ..color = const Color(0xCCFFCDD2); // Pale red, semi-transparent
  final Paint _egg1Paint = Paint()
    ..color = const Color(0xCCFFF9C4); // Pale yellow, semi-transparent
  final Paint _egg2Paint = Paint()
    ..color = const Color(0xCCBBDEFB); // Pale blue, semi-transparent
  final Paint _egg3Paint = Paint()
    ..color = const Color(0xCCF5F5F5); // Pale white, semi-transparent
  final Paint _reinforcedWallPaint = Paint()
    ..color = const Color(0x33FFAB40)
    ..style = PaintingStyle.fill;

  // Room overlay paints (semi-transparent)
  final Paint _homeRoom0Paint = Paint()
    ..color = const Color(0x1A4DD0E1); // Cyan 10%
  final Paint _homeRoom1Paint = Paint()
    ..color = const Color(0x1AFF7043); // Orange 10%
  final Paint _nurseryRoom0Paint = Paint()
    ..color = const Color(0x1AE91E63); // Pink 10%
  final Paint _nurseryRoom1Paint = Paint()
    ..color = const Color(0x1AFF9800); // Amber 10%
  final Paint _foodRoom0Paint = Paint()
    ..color = const Color(0x1A8BC34A); // Green 10%
  final Paint _foodRoom1Paint = Paint()
    ..color = const Color(0x1ACDDC39); // Lime 10%
  final Paint _barracksRoom0Paint = Paint()
    ..color = const Color(0x1A795548); // Brown 10%
  final Paint _barracksRoom1Paint = Paint()
    ..color = const Color(0x1AA1887F); // Light brown 10%
  final Paint _homeRoomBorder0Paint = Paint()
    ..color = const Color(0x334DD0E1)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _homeRoomBorder1Paint = Paint()
    ..color = const Color(0x33FF7043)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _nurseryRoomBorder0Paint = Paint()
    ..color = const Color(0x33E91E63)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _nurseryRoomBorder1Paint = Paint()
    ..color = const Color(0x33FF9800)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _foodRoomBorder0Paint = Paint()
    ..color = const Color(0x338BC34A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _foodRoomBorder1Paint = Paint()
    ..color = const Color(0x33CDDC39)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _barracksRoomBorder0Paint = Paint()
    ..color = const Color(0x33795548)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _barracksRoomBorder1Paint = Paint()
    ..color = const Color(0x33A1887F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  // Stored food item paints (small circles in food room)
  final Paint _storedFood0Paint = Paint()
    ..color = const Color(0xCC76FF03); // Bright green
  final Paint _storedFood1Paint = Paint()
    ..color = const Color(0xCCFFEB3B); // Yellow

  // Cached TextPainters for labels (avoid per-frame allocation)
  static const _nestLabelStyle = TextStyle(
    color: Color(0xFFE0FFB3),
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );
  static const _roomLabelStyle = TextStyle(
    color: Color(0x88FFFFFF),
    fontSize: 8,
  );
  late final TextPainter _colony0LabelPainter = TextPainter(
    text: const TextSpan(text: 'Colony 0', style: _nestLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _colony1LabelPainter = TextPainter(
    text: const TextSpan(text: 'Colony 1', style: _nestLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _colony2LabelPainter = TextPainter(
    text: const TextSpan(text: 'Colony 2', style: _nestLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _colony3LabelPainter = TextPainter(
    text: const TextSpan(text: 'Colony 3', style: _nestLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _homeLabelPainter = TextPainter(
    text: const TextSpan(text: 'Home', style: _roomLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _nurseryLabelPainter = TextPainter(
    text: const TextSpan(text: 'Nursery', style: _roomLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _foodStorageLabelPainter = TextPainter(
    text: const TextSpan(text: 'Food', style: _roomLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  late final TextPainter _barracksLabelPainter = TextPainter(
    text: const TextSpan(text: 'Barracks', style: _roomLabelStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  Picture? _terrainPicture;
  int _cachedTerrainVersion = -1;
  Picture? _pheromonePicture;
  int _pheromoneFrame = 0;
  final List<_DeathPop> _deathPops = [];
  static const double _deathPopDuration = 0.35;

  @override
  void update(double dt) {
    super.update(dt);
    _frameTelemetry.beginUpdate();
    simulation.update(dt);
    _frameTelemetry.endUpdate(dt);
    _collectDeathEvents();
    _updateDeathPops(dt);
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
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyP) {
      simulation.togglePheromones();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyF) {
      simulation.toggleFoodScent();
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

    // Only apply brush in edit mode
    if (!editMode.value) return;

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
    if (!editMode.value) return;
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
    if (!editMode.value) return;
    _applyBrush(event.canvasPosition, _draggingFood);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!editMode.value) return;
    if (_draggingFood || _draggingDig) {
      _applyBrush(event.canvasEndPosition, _draggingFood);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _stopDrag();
  }

  /// Called when pinch/pan gesture starts (from Flutter GestureDetector)
  void onPinchStart() {
    _scaleStartZoom = _zoomFactor;
    _scaleStartPan.setFrom(_panOffset);
  }

  /// Called during pinch/pan gesture (from Flutter GestureDetector)
  void onPinchUpdate(double scale, Offset delta) {
    // Pinch zoom
    final newZoom = (_scaleStartZoom * scale).clamp(0.5, 5.0);
    _zoomFactor = newZoom;

    // Two-finger pan
    _panOffset.x = _scaleStartPan.x + delta.dx;
    _panOffset.y = _scaleStartPan.y + delta.dy;

    _updateViewport();
  }

  void setBrushMode(BrushMode mode) {
    brushMode.value = mode;
  }

  void refreshViewport() {
    _zoomFactor = 1.0; // Reset zoom to fit whole map
    _panOffset.setZero(); // Reset pan
    _recalculateBaseScale();
    _updateViewport();
    invalidateTerrainLayer();
  }

  void setZoom(double zoom) {
    final clamped = zoom.clamp(
      0.1,
      5.0,
    ); // Allow more zoom range for large maps
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

    // Draw room overlays
    _drawRooms(canvas, world, cellSize);
    _drawReinforcedWalls(canvas, world, cellSize);

    final nestPaints = [_nestPaint, _nest1Paint, _nest2Paint, _nest3Paint];
    for (
      var i = 0;
      i < simulation.config.colonyCount && i < world.nestPositions.length;
      i++
    ) {
      final nest = world.nestPositions[i];
      final offset = Offset(nest.x * cellSize, nest.y * cellSize);
      canvas.drawCircle(offset, cellSize * 0.75, nestPaints[i]);
      _drawNestLabel(canvas, offset, i);
    }

    _renderAnts(canvas, cellSize);
  }

  void _drawNestLabel(Canvas canvas, Offset nestOffset, int colonyId) {
    final painter = switch (colonyId) {
      0 => _colony0LabelPainter,
      1 => _colony1LabelPainter,
      2 => _colony2LabelPainter,
      _ => _colony3LabelPainter,
    };
    final offset = nestOffset - Offset(painter.width / 2, painter.height + 6);
    painter.paint(canvas, offset);
  }

  void _drawRooms(Canvas canvas, WorldGrid world, double cellSize) {
    for (final room in world.rooms) {
      final centerOffset = Offset(
        room.center.x * cellSize,
        room.center.y * cellSize,
      );
      final radiusPixels = room.radius * cellSize;

      // Select paints based on room type and colony
      Paint fillPaint;
      Paint borderPaint;
      switch (room.type) {
        case RoomType.home:
          fillPaint = room.colonyId == 0 ? _homeRoom0Paint : _homeRoom1Paint;
          borderPaint = room.colonyId == 0
              ? _homeRoomBorder0Paint
              : _homeRoomBorder1Paint;
        case RoomType.nursery:
          fillPaint = room.colonyId == 0
              ? _nurseryRoom0Paint
              : _nurseryRoom1Paint;
          borderPaint = room.colonyId == 0
              ? _nurseryRoomBorder0Paint
              : _nurseryRoomBorder1Paint;
        case RoomType.foodStorage:
          fillPaint = room.colonyId == 0 ? _foodRoom0Paint : _foodRoom1Paint;
          borderPaint = room.colonyId == 0
              ? _foodRoomBorder0Paint
              : _foodRoomBorder1Paint;
        case RoomType.barracks:
          fillPaint = room.colonyId == 0
              ? _barracksRoom0Paint
              : _barracksRoom1Paint;
          borderPaint = room.colonyId == 0
              ? _barracksRoomBorder0Paint
              : _barracksRoomBorder1Paint;
      }

      // Draw filled circle
      canvas.drawCircle(centerOffset, radiusPixels, fillPaint);
      // Draw border
      canvas.drawCircle(centerOffset, radiusPixels, borderPaint);

      // Draw stored food items in food storage room
      if (room.type == RoomType.foodStorage) {
        _drawStoredFood(canvas, room, cellSize);
      }

      // Draw room label
      _drawRoomLabel(canvas, centerOffset, room);
    }
  }

  void _drawReinforcedWalls(Canvas canvas, WorldGrid world, double cellSize) {
    for (final room in world.rooms) {
      final perimeter = world.getRoomPerimeter(room);
      for (final (x, y) in perimeter) {
        if (!world.isReinforcedCell(x, y)) continue;
        final rect = Rect.fromLTWH(
          x * cellSize,
          y * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, _reinforcedWallPaint);
      }
    }
  }

  void _drawStoredFood(Canvas canvas, Room room, double cellSize) {
    final foodCount = room.colonyId == 0
        ? simulation.colony0Food.value
        : simulation.colony1Food.value;
    if (foodCount == 0) return;

    final paint = room.colonyId == 0 ? _storedFood0Paint : _storedFood1Paint;
    final centerX = room.center.x * cellSize;
    final centerY = room.center.y * cellSize;
    final maxRadius = room.radius * cellSize * 0.7; // Keep items inside room
    final itemRadius = cellSize * 0.25; // Small food circles

    // Display up to 50 food items visually, arranged in spiral pattern
    final displayCount = math.min(foodCount, 50);
    const goldenAngle = 2.39996; // ~137.5 degrees in radians

    for (var i = 0; i < displayCount; i++) {
      // Spiral layout using golden angle
      final angle = i * goldenAngle;
      final dist = maxRadius * math.sqrt(i / displayCount);
      final x = centerX + math.cos(angle) * dist;
      final y = centerY + math.sin(angle) * dist;
      canvas.drawCircle(Offset(x, y), itemRadius, paint);
    }
  }

  void _drawRoomLabel(Canvas canvas, Offset centerOffset, Room room) {
    final TextPainter painter;
    switch (room.type) {
      case RoomType.home:
        painter = _homeLabelPainter;
      case RoomType.nursery:
        painter = _nurseryLabelPainter;
      case RoomType.foodStorage:
        painter = _foodStorageLabelPainter;
      case RoomType.barracks:
        painter = _barracksLabelPainter;
    }
    final offset = centerOffset - Offset(painter.width / 2, painter.height / 2);
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

  Paint _getDirtPaint(DirtType type) {
    switch (type) {
      case DirtType.softSand:
        return _softSandPaint;
      case DirtType.looseSoil:
        return _looseSoilPaint;
      case DirtType.packedEarth:
        return _packedEarthPaint;
      case DirtType.clay:
        return _clayPaint;
      case DirtType.hardite:
        return _harditePaint;
      case DirtType.bedrock:
        return _bedrockPaint;
    }
  }

  Paint _eggPaintForColony(int colonyId) {
    switch (colonyId) {
      case 0:
        return _egg0Paint;
      case 1:
        return _egg1Paint;
      case 2:
        return _egg2Paint;
      default:
        return _egg3Paint;
    }
  }

  Paint _larvaPaintForColony(int colonyId) {
    switch (colonyId) {
      case 0:
        return _larva0Paint;
      case 1:
        return _larva1Paint;
      case 2:
        return _larva2Paint;
      default:
        return _larva3Paint;
    }
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
          final dirtType = world.dirtTypeAt(x, y);
          final paint = _getDirtPaint(dirtType);
          canvas.drawRect(rect, paint);
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
    final showFood = simulation.showFoodPheromones;
    final showHome = simulation.showHomePheromones;
    if (!showFood && !showHome) {
      return;
    }
    // Only iterate over cells with active pheromones
    for (final idx in world.activePheromoneCells) {
      if (world.cells[idx] != CellType.air.index) {
        continue;
      }

      // Get pheromone strengths for both colonies
      var food0 = world.foodPheromones0[idx];
      var home0 = world.homePheromones0[idx];
      var food1 = world.foodPheromones1[idx];
      var home1 = world.homePheromones1[idx];

      if (!showFood) {
        food0 = 0;
        food1 = 0;
      }
      if (!showHome) {
        home0 = 0;
        home1 = 0;
      }

      // Skip if all pheromones are too weak
      if (food0 <= 0.05 && home0 <= 0.05 && food1 <= 0.05 && home1 <= 0.05) {
        continue;
      }

      // Convert index back to x, y coordinates
      final x = idx % cols;
      final y = idx ~/ cols;
      final dx = x * cellSize;
      final dy = y * cellSize;
      final rect = Rect.fromLTWH(dx, dy, cellSize, cellSize);

      final max0 = food0 > home0 ? food0 : home0;
      final max1 = food1 > home1 ? food1 : home1;

      if (max0 >= max1 && max0 > 0.05) {
        final palette = colonyPalettes[0];
        if (food0 >= home0) {
          final alpha = food0.clamp(0, 1).toDouble();
          _foodPheromone0Paint.color = palette.carrying.withValues(
            alpha: alpha,
          );
          canvas.drawRect(rect, _foodPheromone0Paint);
        } else {
          final alpha = home0.clamp(0, 0.8).toDouble();
          _homePheromone0Paint.color = palette.body.withValues(
            alpha: alpha * 0.7,
          );
          canvas.drawRect(rect, _homePheromone0Paint);
        }
      } else if (max1 > 0.05) {
        final palette = colonyPalettes[1];
        if (food1 >= home1) {
          final alpha = food1.clamp(0, 1).toDouble();
          _foodPheromone1Paint.color = palette.carrying.withValues(
            alpha: alpha,
          );
          canvas.drawRect(rect, _foodPheromone1Paint);
        } else {
          final alpha = home1.clamp(0, 0.8).toDouble();
          _homePheromone1Paint.color = palette.body.withValues(
            alpha: alpha * 0.7,
          );
          canvas.drawRect(rect, _homePheromone1Paint);
        }
      }
    }

    // Draw food scent visualization (bright lime green showing smell spreading through tunnels)
    if (simulation.showFoodScent) {
      for (final idx in world.activeFoodScentCells) {
        if (world.cells[idx] != CellType.air.index) {
          continue;
        }
        final scent = world.foodScent[idx];
        if (scent < 0.005) {
          continue;
        }
        final x = idx % cols;
        final y = idx ~/ cols;
        final dx = x * cellSize;
        final dy = y * cellSize;
        final rect = Rect.fromLTWH(dx, dy, cellSize, cellSize);
        final alpha = (scent * 1.2).clamp(0.1, 0.8);
        _foodScentPaint.color = const Color(
          0xFF00FF00,
        ).withValues(alpha: alpha);
        canvas.drawRect(rect, _foodScentPaint);
      }
    }
  }

  void _renderAnts(Canvas canvas, double cellSize) {
    final selected = selectedAnt.value;
    Offset? selectionCenter;
    double selectionRadius = 0;
    final queens = <Ant>[];

    for (final ant in simulation.ants) {
      final center = Offset(
        ant.position.x * cellSize,
        ant.position.y * cellSize,
      );
      final cid = ant.colonyId.clamp(0, 3);

      if (ant.caste == AntCaste.queen) {
        queens.add(ant);
        if (selected?.id == ant.id) {
          selectionCenter = center;
          selectionRadius = selectionRadiusForCaste(ant.caste, cellSize);
        }
        continue;
      }

      if (ant.caste == AntCaste.egg) {
        canvas.drawCircle(center, cellSize * 0.15, _eggPaintForColony(cid));
        if (selected?.id == ant.id) {
          selectionCenter = center;
          selectionRadius = cellSize * 0.25;
        }
        continue;
      }

      if (ant.caste == AntCaste.larva) {
        final rect = Rect.fromCenter(
          center: center,
          width: cellSize * 0.45,
          height: cellSize * 0.25,
        );
        canvas.drawOval(rect, _larvaPaintForColony(cid));
        if (selected?.id == ant.id) {
          selectionCenter = center;
          selectionRadius = cellSize * 0.35;
        }
        continue;
      }

      final bodyColor = bodyColorForColony(cid, carrying: ant.hasFood);
      final accent = accentColorForCaste(ant.caste);
      drawAntSprite(
        canvas: canvas,
        center: center,
        angle: ant.angle,
        cellSize: cellSize,
        caste: ant.caste,
        bodyColor: bodyColor,
        accentColor: accent,
      );

      if (selected?.id == ant.id) {
        selectionCenter = center;
        selectionRadius = selectionRadiusForCaste(ant.caste, cellSize);
      }
    }

    final queenAuraPaints = [
      _queenAura0Paint,
      _queenAura1Paint,
      _queenAura2Paint,
      _queenAura3Paint,
    ];
    final queenAccentColors = [
      _queen0Paint.color,
      _queen1Paint.color,
      _queen2Paint.color,
      _queen3Paint.color,
    ];

    for (final queen in queens) {
      final center = Offset(
        queen.position.x * cellSize,
        queen.position.y * cellSize,
      );
      final cid = queen.colonyId.clamp(0, 3);
      canvas.drawCircle(center, cellSize * 2.5, queenAuraPaints[cid]);
      drawAntSprite(
        canvas: canvas,
        center: center,
        angle: queen.angle,
        cellSize: cellSize * 1.15,
        caste: AntCaste.queen,
        bodyColor: bodyColorForColony(cid, carrying: queen.hasFood),
        accentColor: queenAccentColors[cid],
      );
    }

    if (selectionCenter != null) {
      canvas.drawCircle(selectionCenter, selectionRadius, _selectionPaint);
    }

    for (final pop in _deathPops) {
      final progress = (pop.elapsed / _deathPopDuration).clamp(0.0, 1.0);
      final radius = cellSize * 0.4 * (1 + 0.5 * progress);
      final fade = (1 - progress) * 0.6;
      final paint = Paint()
        ..color = bodyColorForColony(
          pop.colonyId,
          carrying: false,
        ).withValues(alpha: fade);
      canvas.drawCircle(
        Offset(pop.position.x * cellSize, pop.position.y * cellSize),
        radius,
        paint,
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

  void _collectDeathEvents() {
    final events = simulation.takeDeathEvents();
    for (final event in events) {
      _deathPops.add(
        _DeathPop(position: event.position.clone(), colonyId: event.colonyId),
      );
    }
  }

  void _updateDeathPops(double dt) {
    _deathPops.removeWhere((pop) {
      pop.elapsed += dt;
      return pop.elapsed >= _deathPopDuration;
    });
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
    return Vector2(
      px / simulation.config.cellSize,
      py / simulation.config.cellSize,
    );
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
    // Center offset + user pan offset
    _worldOffset
      ..x = (_canvasSize.x - scaledWidth) / 2 + _panOffset.x
      ..y = (_canvasSize.y - scaledHeight) / 2 + _panOffset.y;
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

class _DeathPop {
  _DeathPop({required this.position, required this.colonyId});

  final Vector2 position;
  final int colonyId;
  double elapsed = 0;
}

class FrameTelemetry {
  FrameTelemetry()
    : _logFile = kIsWeb
          ? null
          : File('${Directory.systemTemp.path}/antworld_telemetry.log');

  final Stopwatch _stopwatch = Stopwatch();
  final File? _logFile;
  double _accumulatedTime = 0;
  double _accumulatedUpdateMs = 0;
  int _frames = 0;
  static const double _logInterval = 5.0;

  void beginUpdate() {
    _stopwatch
      ..reset()
      ..start();
  }

  void endUpdate(double dt) {
    _stopwatch.stop();
    _accumulatedTime += dt;
    _accumulatedUpdateMs += _stopwatch.elapsedMicroseconds / 1000.0;
    _frames++;
    if (_accumulatedTime >= _logInterval) {
      final avgUpdate = _accumulatedUpdateMs / _frames;
      final fps = _frames / _accumulatedTime;
      final line =
          '[Telemetry] avgUpdate=${avgUpdate.toStringAsFixed(2)}ms fps=${fps.toStringAsFixed(1)}';
      final file = _logFile;
      if (file != null) {
        try {
          file.writeAsStringSync('$line\n', mode: FileMode.append);
        } catch (_) {}
      } else {
        debugPrint(line);
      }
      _accumulatedTime = 0;
      _accumulatedUpdateMs = 0;
      _frames = 0;
    }
  }
}
