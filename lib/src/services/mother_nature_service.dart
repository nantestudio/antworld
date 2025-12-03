import 'dart:collection';
import 'dart:math' as math;

import 'package:flame/components.dart';

import '../core/event_bus.dart';
import '../core/game_event.dart';
import '../simulation/ant.dart';
import '../simulation/world_grid.dart';
import 'nature_events.dart';

/// Mother Nature - The environmental event system that makes the world feel alive
///
/// This service handles:
/// - Seasonal changes (spring/summer/fall/winter)
/// - Random environmental events (food blooms, collapses, weather, predators)
/// - Frame-distributed event processing for smooth performance
class MotherNatureService {
  MotherNatureService({
    required this.world,
    required this.eventBus,
    required this.getAnts,
    required this.getAntCount,
    required this.spawnPredatorAnt,
    int? seed,
    MotherNatureConfig? config,
  })  : _rng = math.Random(seed ?? DateTime.now().millisecondsSinceEpoch),
        _config = config ?? const MotherNatureConfig();

  final WorldGrid world;
  final GameEventBus eventBus;
  final List<Ant> Function() getAnts;
  final int Function() getAntCount;
  final void Function(Vector2 position, int colonyId, AntCaste caste) spawnPredatorAnt;
  final math.Random _rng;
  final MotherNatureConfig _config;

  // Event queue - process 1 per frame to spread work
  final Queue<NatureEvent> _pendingEvents = Queue();

  // Timers
  double _eventCheckTimer = 0.0;
  int _lastSeason = -1;
  int _currentDay = 0;

  /// Get current season (0=spring, 1=summer, 2=fall, 3=winter)
  Season get currentSeason => _config.getSeason(_currentDay);

  /// Update Mother Nature - call this every frame
  void update(double dt, int daysPassed) {
    if (!_config.enabled) return;

    _currentDay = daysPassed;

    // Check for season change
    final seasonIndex = currentSeason.index;
    if (seasonIndex != _lastSeason) {
      _lastSeason = seasonIndex;
      eventBus.emit(SeasonChangedEvent(
        season: currentSeason.displayName,
        seasonIndex: seasonIndex,
      ));
    }

    // Process one pending event per frame (frame-distributed work)
    if (_pendingEvents.isNotEmpty) {
      _executeEvent(_pendingEvents.removeFirst());
    }

    // Check for new events periodically
    _eventCheckTimer += dt;
    if (_eventCheckTimer >= _config.eventCheckInterval) {
      _rollForEvents();
      _eventCheckTimer = 0.0;
    }
  }

  /// Roll for random events based on current season
  void _rollForEvents() {
    final probs = _config.getEventProbabilities(currentSeason);

    // Winter reduces all event chances
    final winterMultiplier = currentSeason == Season.winter ? 0.3 : 1.0;

    for (final entry in probs.entries) {
      final eventType = entry.key;
      final baseProb = entry.value * winterMultiplier;

      // Skip predator spawn if colony too small
      if (eventType == NatureEventType.predatorSpawn) {
        if (getAntCount() < _config.predatorMinAnts) continue;
      }

      if (_rng.nextDouble() < baseProb) {
        final event = _createEvent(eventType);
        if (event != null) {
          _pendingEvents.add(event);
        }
      }
    }
  }

  /// Create an event instance for the given type
  NatureEvent? _createEvent(NatureEventType type) {
    switch (type) {
      case NatureEventType.foodBloom:
        final pos = _findUnexploredArea() ?? _randomPosition();
        return NatureEvent.foodBloom(pos);

      case NatureEventType.tunnelCollapse:
        final tunnelPos = _findOldTunnelSection();
        if (tunnelPos == null) return null;
        final severity = _rng.nextBool()
            ? CollapseSeverity.soft
            : CollapseSeverity.hard;
        return NatureEvent.tunnelCollapse(tunnelPos, severity);

      case NatureEventType.rockFall:
        final pos = _findTunnelNearSurface();
        if (pos == null) return null;
        return NatureEvent.rockFall(pos);

      case NatureEventType.moisture:
        return NatureEvent.moisture(_randomPosition());

      case NatureEventType.drought:
        return NatureEvent.drought(_randomPosition());

      case NatureEventType.predatorSpawn:
        final pos = _findEdgePosition();
        final raidSize = 5 + _rng.nextInt(10); // 5-15 ants
        return NatureEvent.predatorSpawn(pos, raidSize);

      case NatureEventType.earthquake:
        return NatureEvent.earthquake(_randomPosition());

      case NatureEventType.discovery:
        final pos = _findHiddenChamberLocation();
        if (pos == null) return null;
        return NatureEvent.discovery(pos);
    }
  }

  /// Execute a single event
  void _executeEvent(NatureEvent event) {
    switch (event.type) {
      case NatureEventType.foodBloom:
        _executeFoodBloom(event);
      case NatureEventType.tunnelCollapse:
        _executeTunnelCollapse(event);
      case NatureEventType.rockFall:
        _executeRockFall(event);
      case NatureEventType.moisture:
        _executeMoisture(event);
      case NatureEventType.drought:
        _executeDrought(event);
      case NatureEventType.predatorSpawn:
        _executePredatorSpawn(event);
      case NatureEventType.earthquake:
        _executeEarthquake(event);
      case NatureEventType.discovery:
        _executeDiscovery(event);
    }

    // Emit event for UI notification
    eventBus.emit(NatureEventOccurred(
      eventType: event.type.name,
      positionX: event.position.x,
      positionY: event.position.y,
      message: event.narrativeText,
      isPositive: event.isPositive,
      severity: event.data['severity'] as String?,
    ));
  }

  // ============================================================================
  // Event Implementations
  // ============================================================================

  void _executeFoodBloom(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Place food in a cluster pattern
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        // Only place food in dirt cells (not air, rock, or existing food)
        if (world.cellTypeAt(x, y) == CellType.dirt) {
          // 40% chance to place food in each valid cell
          if (_rng.nextDouble() < 0.4) {
            world.setCell(x, y, CellType.food);
          }
        }
      }
    }
  }

  void _executeTunnelCollapse(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;
    final isHard = event.data['severity'] == CollapseSeverity.hard.name;
    final dirtType = isHard ? DirtType.packedEarth : DirtType.looseSoil;

    // Fill air cells with dirt
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        // Only collapse air cells (tunnels)
        if (world.cellTypeAt(x, y) == CellType.air) {
          // Don't collapse cells with ants in them
          if (!_hasAntAt(x, y)) {
            world.setCell(x, y, CellType.dirt, dirtType: dirtType);
          }
        }
      }
    }
  }

  void _executeRockFall(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Drop rocks into tunnels
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        if (world.cellTypeAt(x, y) == CellType.air) {
          // 30% chance to place a rock
          if (_rng.nextDouble() < 0.3 && !_hasAntAt(x, y)) {
            world.setCell(x, y, CellType.rock);
          }
        }
      }
    }
  }

  void _executeMoisture(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Soften dirt in radius
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        if (world.cellTypeAt(x, y) == CellType.dirt) {
          final current = world.dirtTypeAt(x, y);
          final softer = _softerDirt(current);
          if (softer != current) {
            world.setCell(x, y, CellType.dirt, dirtType: softer);
          }
        }
      }
    }
  }

  void _executeDrought(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Harden dirt in radius
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        if (world.cellTypeAt(x, y) == CellType.dirt) {
          final current = world.dirtTypeAt(x, y);
          final harder = _harderDirt(current);
          if (harder != current) {
            world.setCell(x, y, CellType.dirt, dirtType: harder);
          }
        }
      }
    }
  }

  void _executePredatorSpawn(NatureEvent event) {
    final pos = event.position;
    final raidSize = event.data['raidSize'] as int? ?? 8;
    const predatorColonyId = 99; // Special colony ID for wild raiders

    for (var i = 0; i < raidSize; i++) {
      final offset = Vector2(
        _rng.nextDouble() * 10 - 5,
        _rng.nextDouble() * 10 - 5,
      );
      final spawnPos = pos + offset;

      // 30% soldiers, 70% workers
      final caste = _rng.nextDouble() < 0.3
          ? AntCaste.soldier
          : AntCaste.worker;

      spawnPredatorAnt(spawnPos, predatorColonyId, caste);
    }
  }

  void _executeEarthquake(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Shake loose rocks and some dirt
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        final cell = world.cellTypeAt(x, y);

        // 5% chance to crack rock into dirt
        if (cell == CellType.rock && _rng.nextDouble() < 0.05) {
          world.setCell(x, y, CellType.dirt, dirtType: DirtType.packedEarth);
        }

        // 10% chance to soften hard dirt
        if (cell == CellType.dirt && _rng.nextDouble() < 0.1) {
          final current = world.dirtTypeAt(x, y);
          final softer = _softerDirt(current);
          if (softer != current) {
            world.setCell(x, y, CellType.dirt, dirtType: softer);
          }
        }

        // 3% chance to drop loose rocks into tunnels
        if (cell == CellType.air && _rng.nextDouble() < 0.03) {
          if (!_hasAntAt(x, y)) {
            world.setCell(x, y, CellType.rock);
          }
        }
      }
    }

    // TODO: Add screen shake effect via event
  }

  void _executeDiscovery(NatureEvent event) {
    final pos = event.position;
    final radius = event.radius;

    // Reveal a hidden chamber (carve out space + maybe add treasure)
    for (var dx = -radius; dx <= radius; dx++) {
      for (var dy = -radius; dy <= radius; dy++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        final cell = world.cellTypeAt(x, y);

        // Carve out the chamber
        if (cell == CellType.dirt || cell == CellType.rock) {
          // Edge: 50% chance to keep as soft dirt (natural cave walls)
          final distSq = dx * dx + dy * dy;
          final edgeDist = radius * radius * 0.7;
          if (distSq > edgeDist && _rng.nextDouble() < 0.5) {
            world.setCell(x, y, CellType.dirt, dirtType: DirtType.looseSoil);
          } else {
            world.setCell(x, y, CellType.air);
          }
        }
      }
    }

    // Place some treasure food in the center
    final treasureRadius = radius ~/ 2;
    for (var dx = -treasureRadius; dx <= treasureRadius; dx++) {
      for (var dy = -treasureRadius; dy <= treasureRadius; dy++) {
        if (dx * dx + dy * dy > treasureRadius * treasureRadius) continue;
        final x = (pos.x + dx).floor();
        final y = (pos.y + dy).floor();
        if (!world.isInsideIndex(x, y)) continue;

        // 60% chance to place food
        if (_rng.nextDouble() < 0.6) {
          world.setCell(x, y, CellType.food);
        }
      }
    }

    // Reveal the area (fog of war)
    world.revealArea(pos.x.floor(), pos.y.floor(), radius: radius + 2);
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Find an area that hasn't been explored (no ants have been there)
  Vector2? _findUnexploredArea() {
    // Try 20 random positions
    for (var i = 0; i < 20; i++) {
      final x = _rng.nextInt(world.cols);
      final y = _rng.nextInt(world.rows);

      if (!world.isExplored(x, y) && world.cellTypeAt(x, y) == CellType.dirt) {
        return Vector2(x.toDouble(), y.toDouble());
      }
    }
    return null;
  }

  /// Find an old tunnel section far from nest with no ants nearby
  Vector2? _findOldTunnelSection() {
    final nests = world.nestPositions;
    if (nests.isEmpty) return null;

    // Try 30 random positions
    for (var i = 0; i < 30; i++) {
      final x = _rng.nextInt(world.cols);
      final y = _rng.nextInt(world.rows);

      if (world.cellTypeAt(x, y) != CellType.air) continue;

      // Check distance from all nests
      var farEnough = true;
      for (final nest in nests) {
        final dist = (nest.x - x).abs() + (nest.y - y).abs();
        if (dist < 30) {
          farEnough = false;
          break;
        }
      }

      if (farEnough && !_hasAntNear(x, y, 5)) {
        return Vector2(x.toDouble(), y.toDouble());
      }
    }
    return null;
  }

  /// Find a tunnel near the surface (top of map)
  Vector2? _findTunnelNearSurface() {
    final surfaceLimit = world.rows ~/ 4;

    for (var i = 0; i < 20; i++) {
      final x = _rng.nextInt(world.cols);
      final y = _rng.nextInt(surfaceLimit);

      if (world.cellTypeAt(x, y) == CellType.air) {
        return Vector2(x.toDouble(), y.toDouble());
      }
    }
    return null;
  }

  /// Find a position at the edge of the map
  Vector2 _findEdgePosition() {
    // Pick a random edge (0=top, 1=right, 2=bottom, 3=left)
    final edge = _rng.nextInt(4);
    switch (edge) {
      case 0: // Top
        return Vector2(_rng.nextDouble() * world.cols, 2);
      case 1: // Right
        return Vector2(world.cols - 2.0, _rng.nextDouble() * world.rows);
      case 2: // Bottom
        return Vector2(_rng.nextDouble() * world.cols, world.rows - 2.0);
      default: // Left
        return Vector2(2, _rng.nextDouble() * world.rows);
    }
  }

  /// Find a location for a hidden chamber (in unexplored dense rock/dirt)
  Vector2? _findHiddenChamberLocation() {
    for (var i = 0; i < 20; i++) {
      final x = _rng.nextInt(world.cols);
      final y = _rng.nextInt(world.rows);

      // Must be unexplored and solid
      if (world.isExplored(x, y)) continue;
      if (world.cellTypeAt(x, y) == CellType.air) continue;

      // Must be far from nests
      var farEnough = true;
      for (final nest in world.nestPositions) {
        final dist = (nest.x - x).abs() + (nest.y - y).abs();
        if (dist < 40) {
          farEnough = false;
          break;
        }
      }

      if (farEnough) {
        return Vector2(x.toDouble(), y.toDouble());
      }
    }
    return null;
  }

  /// Get a random position anywhere on the map
  Vector2 _randomPosition() {
    return Vector2(
      _rng.nextDouble() * world.cols,
      _rng.nextDouble() * world.rows,
    );
  }

  /// Check if there's an ant at the given position
  bool _hasAntAt(int x, int y) {
    for (final ant in getAnts()) {
      if (ant.position.x.floor() == x && ant.position.y.floor() == y) {
        return true;
      }
    }
    return false;
  }

  /// Check if there's an ant within radius of position
  bool _hasAntNear(int x, int y, int radius) {
    final radiusSq = radius * radius;
    for (final ant in getAnts()) {
      final dx = ant.position.x - x;
      final dy = ant.position.y - y;
      if (dx * dx + dy * dy < radiusSq) {
        return true;
      }
    }
    return false;
  }

  /// Get one tier softer dirt type
  DirtType _softerDirt(DirtType current) {
    switch (current) {
      case DirtType.bedrock:
        return DirtType.hardite;
      case DirtType.hardite:
        return DirtType.clay;
      case DirtType.clay:
        return DirtType.packedEarth;
      case DirtType.packedEarth:
        return DirtType.looseSoil;
      case DirtType.looseSoil:
        return DirtType.softSand;
      case DirtType.softSand:
        return DirtType.softSand; // Already softest
    }
  }

  /// Get one tier harder dirt type
  DirtType _harderDirt(DirtType current) {
    switch (current) {
      case DirtType.softSand:
        return DirtType.looseSoil;
      case DirtType.looseSoil:
        return DirtType.packedEarth;
      case DirtType.packedEarth:
        return DirtType.clay;
      case DirtType.clay:
        return DirtType.hardite;
      case DirtType.hardite:
        return DirtType.bedrock;
      case DirtType.bedrock:
        return DirtType.bedrock; // Already hardest
    }
  }
}
