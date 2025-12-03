import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_event.dart';

/// Displays the current season with an icon
class SeasonIndicator extends StatefulWidget {
  const SeasonIndicator({
    super.key,
    required this.eventStream,
    this.initialSeason = 'Spring',
  });

  final Stream<SeasonChangedEvent> eventStream;
  final String initialSeason;

  @override
  State<SeasonIndicator> createState() => _SeasonIndicatorState();
}

class _SeasonIndicatorState extends State<SeasonIndicator>
    with SingleTickerProviderStateMixin {
  late String _currentSeason;
  StreamSubscription<SeasonChangedEvent>? _subscription;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _currentSeason = widget.initialSeason;

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _subscription = widget.eventStream.listen(_onSeasonChanged);
  }

  void _onSeasonChanged(SeasonChangedEvent event) {
    setState(() {
      _currentSeason = event.season;
    });
    // Pulse animation when season changes
    _pulseController.forward().then((_) => _pulseController.reverse());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _getSeasonIcon(String season) {
    switch (season.toLowerCase()) {
      case 'spring':
        return '🌸';
      case 'summer':
        return '☀';
      case 'fall':
        return '🍂';
      case 'winter':
        return '❄';
      default:
        return '🌍';
    }
  }

  Color _getSeasonColor(String season) {
    switch (season.toLowerCase()) {
      case 'spring':
        return const Color(0xFFE91E63); // Pink
      case 'summer':
        return const Color(0xFFFF9800); // Orange
      case 'fall':
        return const Color(0xFF795548); // Brown
      case 'winter':
        return const Color(0xFF03A9F4); // Light blue
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _getSeasonIcon(_currentSeason);
    final color = _getSeasonColor(_currentSeason);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.2);
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 4),
            Text(
              _currentSeason,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
