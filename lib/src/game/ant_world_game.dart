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
  final ValueNotifier<bool> editMode = ValueNotifier<bool>(false); // Default: navigation mode

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
  final Paint _softSandPaint = Paint()..color = const Color(0xFFD7CCC8);   // Light tan
  final Paint _looseSoilPaint = Paint()..color = const Color(0xFFA1887F);  // Sandy brown
  final Paint _packedEarthPaint = Paint()..color = const Color(0xFF795548); // Medium brown
  final Paint _clayPaint = Paint()..color = const Color(0xFF5D4037);       // Dark brown
  final Paint _harditePaint = Paint()..color = const Color(0xFF8D6E63);    // Reddish-brown
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
  // Queen paints (larger, with aura)
  final Paint _queen0Paint = Paint()..color = const Color(0xFF00BCD4); // Darker cyan
  final Paint _queen1Paint = Paint()..color = const Color(0xFFFF5722); // Darker orange
  final Paint _queenAura0Paint = Paint()..color = const Color(0x3300BCD4); // Transparent cyan
  final Paint _queenAura1Paint = Paint()..color = const Color(0x33FF5722); // Transparent orange
  // Larva paint (smaller, lighter)
  final Paint _larva0Paint = Paint()..color = const Color(0x99B2EBF2); // Light cyan, semi-transparent
  final Paint _larva1Paint = Paint()..color = const Color(0x99FFCCBC); // Light orange, semi-transparent
  // Egg paint (tiny, yellowish)
  final Paint _egg0Paint = Paint()..color = const Color(0xCCFFF9C4); // Pale yellow, semi-transparent
  final Paint _egg1Paint = Paint()..color = const Color(0xCCFFE082); // Light amber, semi-transparent

  // Room overlay paints (semi-transparent)
  final Paint _homeRoom0Paint = Paint()..color = const Color(0x1A4DD0E1); // Cyan 10%
  final Paint _homeRoom1Paint = Paint()..color = const Color(0x1AFF7043); // Orange 10%
  final Paint _nurseryRoom0Paint = Paint()..color = const Color(0x1AE91E63); // Pink 10%
  final Paint _nurseryRoom1Paint = Paint()..color = const Color(0x1AFF9800); // Amber 10%
  final Paint _foodRoom0Paint = Paint()..color = const Color(0x1A8BC34A); // Green 10%
  final Paint _foodRoom1Paint = Paint()..color = const Color(0x1ACDDC39); // Lime 10%
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

    // Draw room overlays
    _drawRooms(canvas, world, cellSize);

    // Render colony 0 nest (cyan)
    final nest0 = world.nestPosition;
    final nest0Offset = Offset(nest0.x * cellSize, nest0.y * cellSize);
    canvas.drawCircle(nest0Offset, cellSize * 0.75, _nestPaint);
    _drawNestLabel(canvas, nest0Offset, 0);

    // Render colony 1 nest (orange)
    final nest1 = world.nest1Position;
    final nest1Offset = Offset(nest1.x * cellSize, nest1.y * cellSize);
    canvas.drawCircle(nest1Offset, cellSize * 0.75, _nest1Paint);
    _drawNestLabel(canvas, nest1Offset, 1);

    _renderAnts(canvas, cellSize);
  }

  void _drawNestLabel(Canvas canvas, Offset nestOffset, int colonyId) {
    final painter = colonyId == 0 ? _colony0LabelPainter : _colony1LabelPainter;
    final offset = nestOffset - Offset(painter.width / 2, painter.height + 6);
    painter.paint(canvas, offset);
  }

  void _drawRooms(Canvas canvas, WorldGrid world, double cellSize) {
    for (final room in world.rooms) {
      final centerOffset = Offset(room.center.x * cellSize, room.center.y * cellSize);
      final radiusPixels = room.radius * cellSize;

      // Select paints based on room type and colony
      Paint fillPaint;
      Paint borderPaint;
      switch (room.type) {
        case RoomType.home:
          fillPaint = room.colonyId == 0 ? _homeRoom0Paint : _homeRoom1Paint;
          borderPaint = room.colonyId == 0 ? _homeRoomBorder0Paint : _homeRoomBorder1Paint;
        case RoomType.nursery:
          fillPaint = room.colonyId == 0 ? _nurseryRoom0Paint : _nurseryRoom1Paint;
          borderPaint = room.colonyId == 0 ? _nurseryRoomBorder0Paint : _nurseryRoomBorder1Paint;
        case RoomType.foodStorage:
          fillPaint = room.colonyId == 0 ? _foodRoom0Paint : _foodRoom1Paint;
          borderPaint = room.colonyId == 0 ? _foodRoomBorder0Paint : _foodRoomBorder1Paint;
      }

      // Draw filled circle
      canvas.drawCircle(centerOffset, radiusPixels, fillPaint);
      // Draw border
      canvas.drawCircle(centerOffset, radiusPixels, borderPaint);

      // Draw room label
      _drawRoomLabel(canvas, centerOffset, room);
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
    // Only iterate over cells with active pheromones
    for (final idx in world.activePheromoneCells) {
      if (world.cells[idx] != CellType.air.index) {
        continue;
      }

      // Get pheromone strengths for both colonies
      final food0 = world.foodPheromones0[idx];
      final home0 = world.homePheromones0[idx];
      final food1 = world.foodPheromones1[idx];
      final home1 = world.homePheromones1[idx];

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

      // Draw strongest pheromone for each colony (blend if both present)
      // Colony 0: blue for food, gray for home
      final max0 = food0 > home0 ? food0 : home0;
      // Colony 1: orange for food, purple for home
      final max1 = food1 > home1 ? food1 : home1;

      if (max0 >= max1 && max0 > 0.05) {
        // Colony 0 dominates
        if (food0 >= home0) {
          final alpha = food0.clamp(0, 1).toDouble();
          _foodPheromone0Paint.color =
              const Color(0xFF0064FF).withValues(alpha: alpha);
          canvas.drawRect(rect, _foodPheromone0Paint);
        } else {
          final alpha = home0.clamp(0, 0.6).toDouble();
          _homePheromone0Paint.color =
              const Color(0xFF888888).withValues(alpha: alpha);
          canvas.drawRect(rect, _homePheromone0Paint);
        }
      } else if (max1 > 0.05) {
        // Colony 1 dominates
        if (food1 >= home1) {
          final alpha = food1.clamp(0, 1).toDouble();
          _foodPheromone1Paint.color =
              const Color(0xFFFF6400).withValues(alpha: alpha);
          canvas.drawRect(rect, _foodPheromone1Paint);
        } else {
          final alpha = home1.clamp(0, 0.6).toDouble();
          _homePheromone1Paint.color =
              const Color(0xFF884488).withValues(alpha: alpha);
          canvas.drawRect(rect, _homePheromone1Paint);
        }
      }
    }
  }

  void _renderAnts(Canvas canvas, double cellSize) {
    // Colony 0 paths (cyan/green tones)
    final colony0Path = Path();
    final colony0CarryingPath = Path();
    final larva0Path = Path();
    final egg0Path = Path();
    // Colony 1 paths (orange/red tones)
    final colony1Path = Path();
    final colony1CarryingPath = Path();
    final larva1Path = Path();
    final egg1Path = Path();

    var colony0HasContent = false;
    var colony0CarryingHasContent = false;
    var larva0HasContent = false;
    var egg0HasContent = false;
    var colony1HasContent = false;
    var colony1CarryingHasContent = false;
    var larva1HasContent = false;
    var egg1HasContent = false;

    // Collect queens to draw separately (on top, with aura)
    final queens = <Ant>[];

    final radius = cellSize * 0.35;
    final larvaRadius = cellSize * 0.2; // Smaller for larvae
    final eggRadius = cellSize * 0.12; // Tiny for eggs
    for (final Ant ant in simulation.ants) {
      final center = Offset(ant.position.x * cellSize, ant.position.y * cellSize);

      // Queens drawn separately with aura
      if (ant.caste == AntCaste.queen) {
        queens.add(ant);
        continue;
      }

      // Eggs are tiny
      if (ant.caste == AntCaste.egg) {
        final rect = Rect.fromCircle(center: center, radius: eggRadius);
        if (ant.colonyId == 0) {
          egg0Path.addOval(rect);
          egg0HasContent = true;
        } else {
          egg1Path.addOval(rect);
          egg1HasContent = true;
        }
        continue;
      }

      // Larvae are smaller
      if (ant.caste == AntCaste.larva) {
        final rect = Rect.fromCircle(center: center, radius: larvaRadius);
        if (ant.colonyId == 0) {
          larva0Path.addOval(rect);
          larva0HasContent = true;
        } else {
          larva1Path.addOval(rect);
          larva1HasContent = true;
        }
        continue;
      }

      // Regular ants
      final rect = Rect.fromCircle(center: center, radius: radius);
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

    // Draw eggs first (background, smallest)
    if (egg0HasContent) {
      canvas.drawPath(egg0Path, _egg0Paint);
    }
    if (egg1HasContent) {
      canvas.drawPath(egg1Path, _egg1Paint);
    }

    // Draw larvae (background, small)
    if (larva0HasContent) {
      canvas.drawPath(larva0Path, _larva0Paint);
    }
    if (larva1HasContent) {
      canvas.drawPath(larva1Path, _larva1Paint);
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

    // Draw queens last (on top) with aura and 2x size
    final queenRadius = cellSize * 0.7; // 2x normal size
    final auraRadius = cellSize * 2.5;  // Large transparent aura
    for (final queen in queens) {
      final center = Offset(queen.position.x * cellSize, queen.position.y * cellSize);
      // Draw aura first (behind queen)
      if (queen.colonyId == 0) {
        canvas.drawCircle(center, auraRadius, _queenAura0Paint);
        canvas.drawCircle(center, queenRadius, _queen0Paint);
      } else {
        canvas.drawCircle(center, auraRadius, _queenAura1Paint);
        canvas.drawCircle(center, queenRadius, _queen1Paint);
      }
    }

    // Draw selection highlight
    final selected = selectedAnt.value;
    if (selected != null) {
      double selectionRadius;
      if (selected.caste == AntCaste.queen) {
        selectionRadius = cellSize * 1.0; // Larger selection for queen
      } else if (selected.caste == AntCaste.egg) {
        selectionRadius = cellSize * 0.3; // Small selection for egg
      } else if (selected.caste == AntCaste.larva) {
        selectionRadius = cellSize * 0.4; // Smaller selection for larva
      } else {
        selectionRadius = cellSize * 0.6; // Regular ants
      }
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
