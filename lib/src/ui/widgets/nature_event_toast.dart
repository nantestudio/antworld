import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_event.dart';

/// Toast notification for Mother Nature events
class NatureEventToast extends StatefulWidget {
  const NatureEventToast({
    super.key,
    required this.event,
    this.duration = const Duration(seconds: 4),
    this.onDismiss,
  });

  final NatureEventOccurred event;
  final Duration duration;
  final VoidCallback? onDismiss;

  @override
  State<NatureEventToast> createState() => _NatureEventToastState();
}

class _NatureEventToastState extends State<NatureEventToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: -50, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _getIcon(String eventType) {
    switch (eventType) {
      case 'foodBloom':
        return '🌿';
      case 'tunnelCollapse':
        return '💨';
      case 'rockFall':
        return '🪨';
      case 'moisture':
        return '🌧';
      case 'drought':
        return '☀';
      case 'predatorSpawn':
        return '🐜';
      case 'earthquake':
        return '🌋';
      case 'discovery':
        return '✨';
      default:
        return '🌍';
    }
  }

  Color _getBackgroundColor(bool isPositive) {
    return isPositive
        ? const Color(0xFF2E7D32).withValues(alpha: 0.9) // Green
        : const Color(0xFFC62828).withValues(alpha: 0.9); // Red
  }

  Color _getBorderColor(bool isPositive) {
    return isPositive
        ? const Color(0xFF4CAF50) // Light green
        : const Color(0xFFEF5350); // Light red
  }

  @override
  Widget build(BuildContext context) {
    final icon = _getIcon(widget.event.eventType);
    final bgColor = _getBackgroundColor(widget.event.isPositive);
    final borderColor = _getBorderColor(widget.event.isPositive);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.event.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Container that manages displaying nature event toasts
class NatureEventToastContainer extends StatefulWidget {
  const NatureEventToastContainer({
    super.key,
    required this.eventStream,
    this.maxToasts = 3,
  });

  final Stream<NatureEventOccurred> eventStream;
  final int maxToasts;

  @override
  State<NatureEventToastContainer> createState() =>
      _NatureEventToastContainerState();
}

class _NatureEventToastContainerState extends State<NatureEventToastContainer> {
  final List<NatureEventOccurred> _activeToasts = [];
  StreamSubscription<NatureEventOccurred>? _subscription;
  int _toastId = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.eventStream.listen(_onEvent);
  }

  void _onEvent(NatureEventOccurred event) {
    if (_activeToasts.length >= widget.maxToasts) {
      _activeToasts.removeAt(0);
    }
    setState(() {
      _activeToasts.add(event);
    });
  }

  void _removeToast(NatureEventOccurred event) {
    setState(() {
      _activeToasts.remove(event);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Column(
        children: _activeToasts.map((event) {
          return NatureEventToast(
            key: ValueKey('toast_${_toastId++}_${event.eventType}'),
            event: event,
            onDismiss: () => _removeToast(event),
          );
        }).toList(),
      ),
    );
  }
}
