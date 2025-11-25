import 'package:flutter/material.dart';

import '../simulation/ant.dart';
import '../visuals/ant_sprite.dart';

class AntGalleryPage extends StatelessWidget {
  const AntGalleryPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to menu',
            ),
            const SizedBox(width: 8),
            const Text(
              'Ant Castes',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final entry = _antTypes[index];
              return _AntTypeCard(entry: entry);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: _antTypes.length,
          ),
        ),
      ],
    );
  }
}

class _AntTypeCard extends StatelessWidget {
  const _AntTypeCard({required this.entry});

  final _AntTypeInfo entry;

  @override
  Widget build(BuildContext context) {
    final bodyColor = bodyColorForColony(0, carrying: false);
    final accent = entry.caste == AntCaste.queen
        ? colonyPalettes.first.body
        : accentColorForCaste(entry.caste);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _AntSamplePainter(
                  caste: entry.caste,
                  bodyColor: bodyColor,
                  accentColor: accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              entry.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AntSamplePainter extends CustomPainter {
  const _AntSamplePainter({
    required this.caste,
    required this.bodyColor,
    this.accentColor,
  });

  final AntCaste caste;
  final Color bodyColor;
  final Color? accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final cellSize = size.shortestSide * 0.6;
    if (caste == AntCaste.egg) {
      canvas.drawCircle(
        center,
        cellSize * 0.15,
        Paint()..color = const Color(0xCCFFCDD2),
      );
    } else if (caste == AntCaste.larva) {
      final rect = Rect.fromCenter(
        center: center,
        width: cellSize * 0.45,
        height: cellSize * 0.25,
      );
      canvas.drawOval(rect, Paint()..color = const Color(0x99EF9A9A));
    } else {
      drawAntSprite(
        canvas: canvas,
        center: center,
        angle: 0,
        cellSize: cellSize,
        caste: caste,
        bodyColor: bodyColor,
        accentColor: accentColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AntSamplePainter oldDelegate) {
    return oldDelegate.caste != caste ||
        oldDelegate.bodyColor != bodyColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _AntTypeInfo {
  const _AntTypeInfo({
    required this.caste,
    required this.title,
    required this.description,
  });

  final AntCaste caste;
  final String title;
  final String description;
}

const List<_AntTypeInfo> _antTypes = [
  _AntTypeInfo(
    caste: AntCaste.worker,
    title: 'Worker',
    description:
        'Core foragers that dig tunnels, haul food, and expand the nest.',
  ),
  _AntTypeInfo(
    caste: AntCaste.builder,
    title: 'Builder',
    description:
        'Specialized workers that reinforce walls and carve new rooms.',
  ),
  _AntTypeInfo(
    caste: AntCaste.soldier,
    title: 'Soldier',
    description:
        'High-armor defenders that patrol for threats and guard chokepoints.',
  ),
  _AntTypeInfo(
    caste: AntCaste.nurse,
    title: 'Nurse',
    description:
        'Tend to eggs and larvae, ferrying them between the queen and nursery.',
  ),
  _AntTypeInfo(
    caste: AntCaste.princess,
    title: 'Princess',
    description:
        'Future queens that stay near the royal chamber until succession.',
  ),
  _AntTypeInfo(
    caste: AntCaste.queen,
    title: 'Queen',
    description:
        'The heart of the colony—lays eggs and anchors pheromone guidance.',
  ),
  _AntTypeInfo(
    caste: AntCaste.drone,
    title: 'Drone',
    description:
        'Support caste with long-range scouting and emergency foraging duties.',
  ),
  _AntTypeInfo(
    caste: AntCaste.larva,
    title: 'Larva',
    description:
        'Immature ants that require nurse care before maturing into a caste.',
  ),
  _AntTypeInfo(
    caste: AntCaste.egg,
    title: 'Egg',
    description:
        'Freshly laid eggs that will hatch into larvae once moved to the nursery.',
  ),
];
