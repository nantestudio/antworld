import 'package:flame/components.dart';

/// Types of events that Mother Nature can trigger
enum NatureEventType {
  /// New food appears in unexplored areas
  foodBloom,

  /// Tunnel section collapses back to dirt
  tunnelCollapse,

  /// Small rocks fall into tunnels
  rockFall,

  /// Area becomes easier to dig (spring rain)
  moisture,

  /// Area hardens (summer heat)
  drought,

  /// Enemy ant raid from the surface
  predatorSpawn,

  /// Screen shake + loose rocks
  earthquake,

  /// Hidden chamber revealed nearby
  discovery,
}

/// Severity level for collapse events
enum CollapseSeverity {
  /// Soft collapse - loose soil, easy to re-dig
  soft,

  /// Hard collapse - packed earth, challenging to rebuild
  hard,
}

/// Seasons that affect event probabilities
enum Season {
  spring, // Day 0-6, 28-34, etc. - More food blooms, moisture
  summer, // Day 7-13, 35-41, etc. - More drought
  fall, // Day 14-20, 42-48, etc. - Balanced
  winter, // Day 21-27, 49-55, etc. - Fewer events overall
}

extension SeasonExtension on Season {
  String get displayName {
    switch (this) {
      case Season.spring:
        return 'Spring';
      case Season.summer:
        return 'Summer';
      case Season.fall:
        return 'Fall';
      case Season.winter:
        return 'Winter';
    }
  }

  String get icon {
    switch (this) {
      case Season.spring:
        return '🌸';
      case Season.summer:
        return '☀️';
      case Season.fall:
        return '🍂';
      case Season.winter:
        return '❄️';
    }
  }
}

/// A pending or active nature event
class NatureEvent {
  const NatureEvent({
    required this.type,
    required this.position,
    this.radius = 8,
    this.data = const {},
    this.narrativeText = '',
  });

  /// The type of event
  final NatureEventType type;

  /// World position where the event occurs
  final Vector2 position;

  /// Radius of effect (cells)
  final int radius;

  /// Additional event-specific data
  final Map<String, dynamic> data;

  /// Human-readable narrative text for UI
  final String narrativeText;

  /// Create a food bloom event
  factory NatureEvent.foodBloom(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.foodBloom,
      position: position,
      radius: 4,
      narrativeText: 'Rich food source discovered!',
    );
  }

  /// Create a tunnel collapse event
  factory NatureEvent.tunnelCollapse(
    Vector2 position,
    CollapseSeverity severity,
  ) {
    final isHard = severity == CollapseSeverity.hard;
    return NatureEvent(
      type: NatureEventType.tunnelCollapse,
      position: position,
      radius: 6,
      data: {'severity': severity.name},
      narrativeText: isHard
          ? 'A major cave-in blocked the tunnel!'
          : 'A tunnel section has collapsed...',
    );
  }

  /// Create a rock fall event
  factory NatureEvent.rockFall(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.rockFall,
      position: position,
      radius: 3,
      narrativeText: 'Rocks tumble down from above!',
    );
  }

  /// Create a moisture event (softens dirt)
  factory NatureEvent.moisture(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.moisture,
      position: position,
      radius: 12,
      narrativeText: 'Spring rain softens the earth...',
    );
  }

  /// Create a drought event (hardens dirt)
  factory NatureEvent.drought(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.drought,
      position: position,
      radius: 12,
      narrativeText: 'Summer heat bakes the ground...',
    );
  }

  /// Create a predator spawn event (enemy ant raid)
  factory NatureEvent.predatorSpawn(Vector2 position, int raidSize) {
    return NatureEvent(
      type: NatureEventType.predatorSpawn,
      position: position,
      radius: 5,
      data: {'raidSize': raidSize},
      narrativeText: 'Hostile ants are raiding from the surface!',
    );
  }

  /// Create an earthquake event
  factory NatureEvent.earthquake(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.earthquake,
      position: position,
      radius: 20,
      narrativeText: 'The ground trembles violently!',
    );
  }

  /// Create a discovery event (hidden chamber revealed)
  factory NatureEvent.discovery(Vector2 position) {
    return NatureEvent(
      type: NatureEventType.discovery,
      position: position,
      radius: 5,
      narrativeText: 'A hidden chamber has been revealed!',
    );
  }

  /// Icon for this event type
  String get icon {
    switch (type) {
      case NatureEventType.foodBloom:
        return '🌿';
      case NatureEventType.tunnelCollapse:
        return '💨';
      case NatureEventType.rockFall:
        return '🪨';
      case NatureEventType.moisture:
        return '🌧️';
      case NatureEventType.drought:
        return '☀️';
      case NatureEventType.predatorSpawn:
        return '🐜';
      case NatureEventType.earthquake:
        return '🌋';
      case NatureEventType.discovery:
        return '✨';
    }
  }

  /// Whether this is a positive event for the player
  bool get isPositive {
    switch (type) {
      case NatureEventType.foodBloom:
      case NatureEventType.moisture:
      case NatureEventType.discovery:
        return true;
      case NatureEventType.tunnelCollapse:
      case NatureEventType.rockFall:
      case NatureEventType.drought:
      case NatureEventType.predatorSpawn:
      case NatureEventType.earthquake:
        return false;
    }
  }
}

/// Configuration for Mother Nature event system
class MotherNatureConfig {
  const MotherNatureConfig({
    this.enabled = true,
    this.eventCheckInterval = 30.0,
    this.seasonLengthDays = 7,
    this.foodBloomBaseProb = 0.05,
    this.tunnelCollapseProb = 0.03,
    this.rockFallProb = 0.05,
    this.moistureBaseProb = 0.02,
    this.droughtBaseProb = 0.02,
    this.predatorSpawnProb = 0.05,
    this.predatorMinAnts = 50,
    this.earthquakeProb = 0.01,
    this.discoveryProb = 0.08,
  });

  /// Whether Mother Nature events are enabled
  final bool enabled;

  /// Seconds between event checks (game time)
  final double eventCheckInterval;

  /// Days per season
  final int seasonLengthDays;

  /// Base probability for food bloom (boosted in spring)
  final double foodBloomBaseProb;

  /// Probability for tunnel collapse
  final double tunnelCollapseProb;

  /// Probability for rock fall
  final double rockFallProb;

  /// Base probability for moisture (boosted in spring)
  final double moistureBaseProb;

  /// Base probability for drought (boosted in summer)
  final double droughtBaseProb;

  /// Probability for predator spawn (only when colony > minAnts)
  final double predatorSpawnProb;

  /// Minimum ant count before predators can spawn
  final int predatorMinAnts;

  /// Probability for earthquake (very rare)
  final double earthquakeProb;

  /// Probability for discovery events
  final double discoveryProb;

  /// Default configuration
  static const defaultConfig = MotherNatureConfig();

  /// Get current season from day number
  Season getSeason(int day) {
    final seasonIndex = (day ~/ seasonLengthDays) % 4;
    return Season.values[seasonIndex];
  }

  /// Get event probabilities adjusted for current season
  Map<NatureEventType, double> getEventProbabilities(Season season) {
    return {
      NatureEventType.foodBloom:
          season == Season.spring ? foodBloomBaseProb * 3 : foodBloomBaseProb,
      NatureEventType.tunnelCollapse: tunnelCollapseProb,
      NatureEventType.rockFall: rockFallProb,
      NatureEventType.moisture:
          season == Season.spring ? moistureBaseProb * 5 : moistureBaseProb,
      NatureEventType.drought:
          season == Season.summer ? droughtBaseProb * 5 : droughtBaseProb,
      NatureEventType.predatorSpawn: predatorSpawnProb,
      NatureEventType.earthquake: earthquakeProb,
      NatureEventType.discovery: discoveryProb,
    };
  }
}
