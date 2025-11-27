import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../simulation/level_layout.dart';
import '../../simulation/simulation_config.dart';
import '../../simulation/world_generator.dart';
import '../../simulation/world_grid.dart';

/// Renders a tiny minimap of a generated world for quick layout inspection.
class LevelPreview extends StatefulWidget {
  const LevelPreview({super.key, required this.layout});

  final LevelLayout layout;

  @override
  State<LevelPreview> createState() => _LevelPreviewState();
}

class _LevelPreviewState extends State<LevelPreview> {
  WorldGrid? _world;

  @override
  void initState() {
    super.initState();
    _buildWorld();
  }

  @override
  void didUpdateWidget(LevelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.id != widget.layout.id ||
        oldWidget.layout.seed != widget.layout.seed) {
      _buildWorld();
    }
  }

  void _buildWorld() {
    final generator = WorldGenerator();
    final generated = generator.generate(
      baseConfig: defaultSimulationConfig,
      seed: widget.layout.seed,
      cols: widget.layout.cols,
      rows: widget.layout.rows,
      colonyCount: widget.layout.colonyCount,
      layout: widget.layout,
    );
    setState(() => _world = generated.world);
  }

  @override
  Widget build(BuildContext context) {
    final world = _world;
    if (world == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      height: 160,
      child: CustomPaint(
        painter: _LevelMiniMapPainter(world),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LevelMiniMapPainter extends CustomPainter {
  _LevelMiniMapPainter(this.world);

  final WorldGrid world;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = world.cols;
    final rows = world.rows;
    final scaleX = size.width / cols;
    final scaleY = size.height / rows;

    final paint = Paint()..style = PaintingStyle.fill;

    final rects = <Rect>[];
    final colors = <ui.Color>[];

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final idx = world.index(x, y);
        final cellType = CellType.values[world.cells[idx]];
        Color color;
        switch (cellType) {
          case CellType.air:
            color = const Color(0xFF0D0D0D);
          case CellType.dirt:
            final dirt = DirtType.values[world.dirtTypes[idx]];
            color = switch (dirt) {
              DirtType.softSand => const Color(0xFFBFA27A),
              DirtType.looseSoil => const Color(0xFF9C7A5D),
              DirtType.packedEarth => const Color(0xFF6E4E35),
              DirtType.clay => const Color(0xFF5A3B2C),
              DirtType.hardite => const Color(0xFF3E2B23),
              DirtType.bedrock => const Color(0xFF2B2725),
            };
          case CellType.food:
            color = const Color(0xFF62F08A);
          case CellType.rock:
            color = const Color(0xFF666666);
        }
        rects.add(Rect.fromLTWH(x * scaleX, y * scaleY, scaleX, scaleY));
        colors.add(color);
      }
    }

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (var i = 0; i < rects.length; i++) {
      paint.color = colors[i];
      canvas.drawRect(rects[i], paint);
    }

    // Draw nest markers
    paint
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.fill;
    for (final nest in world.nestPositions) {
      canvas.drawCircle(
        Offset(nest.x * scaleX, nest.y * scaleY),
        4,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LevelMiniMapPainter oldDelegate) {
    return oldDelegate.world != world;
  }
}
