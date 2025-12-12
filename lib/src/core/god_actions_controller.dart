import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';

import '../simulation/colony_simulation.dart';

enum GodActionType { digBurst, foodDrop, rockWall }

class GodActionState {
  const GodActionState({
    required this.charges,
    required this.maxCharges,
    required this.cooldownEndsAt,
  });

  final int charges;
  final int maxCharges;
  final DateTime cooldownEndsAt;
}

class GodActionsController {
  GodActionsController();

  final Map<GodActionType, int> _charges = {
    GodActionType.digBurst: 2,
    GodActionType.foodDrop: 2,
    GodActionType.rockWall: 1,
  };
  final Map<GodActionType, int> _maxCharges = {
    GodActionType.digBurst: 3,
    GodActionType.foodDrop: 3,
    GodActionType.rockWall: 2,
  };
  final Map<GodActionType, Duration> _cooldowns = {
    GodActionType.digBurst: const Duration(seconds: 90),
    GodActionType.foodDrop: const Duration(seconds: 120),
    GodActionType.rockWall: const Duration(seconds: 180),
  };
  final Map<GodActionType, DateTime> _cooldownEnds = {
    GodActionType.digBurst: DateTime.fromMillisecondsSinceEpoch(0),
    GodActionType.foodDrop: DateTime.fromMillisecondsSinceEpoch(0),
    GodActionType.rockWall: DateTime.fromMillisecondsSinceEpoch(0),
  };

  final StreamController<void> _changes = StreamController.broadcast();
  Stream<void> get changes => _changes.stream;

  GodActionState state(GodActionType type) {
    return GodActionState(
      charges: _charges[type] ?? 0,
      maxCharges: _maxCharges[type] ?? 0,
      cooldownEndsAt: _cooldownEnds[type] ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Duration cooldownRemaining(GodActionType type) {
    final now = DateTime.now();
    final end = _cooldownEnds[type] ?? now;
    if (end.isBefore(now)) return Duration.zero;
    return end.difference(now);
  }

  bool canUse(GodActionType type) {
    return (_charges[type] ?? 0) > 0 && cooldownRemaining(type) == Duration.zero;
  }

  Future<bool> use(GodActionType type, ColonySimulation sim) async {
    if (!canUse(type)) return false;
    _charges[type] = (_charges[type] ?? 0) - 1;
    _cooldownEnds[type] = DateTime.now().add(_cooldowns[type]!);
    switch (type) {
      case GodActionType.digBurst:
        _applyDigBurst(sim);
      case GodActionType.foodDrop:
        sim.dropBonusFood(50);
      case GodActionType.rockWall:
        _applyRockWall(sim);
    }
    _changes.add(null);
    return true;
  }

  void _applyDigBurst(ColonySimulation sim) {
    final nest = sim.world.nestPosition;
    final rng = math.Random();
    final pos = nest +
        Vector2(
          (rng.nextDouble() - 0.5) * 6,
          (rng.nextDouble() - 0.5) * 6,
        );
    sim.world.digCircle(pos, 3);
  }

  void _applyRockWall(ColonySimulation sim) {
    final nest = sim.world.nestPosition;
    final rng = math.Random();
    // Place a small hardite cluster away from the nest entrance
    final pos = nest +
        Vector2(
          (rng.nextDouble() - 0.5) * 12,
          (rng.nextDouble() - 0.5) * 12,
        );
    sim.world.placeHardite(pos, 2);
  }

  void dispose() {
    _changes.close();
  }
}
