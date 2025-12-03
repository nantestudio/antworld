/// Data models for the AI Hive Mind system
library;

/// Snapshot of colony state sent to AI for decision making
class HiveMindStateSnapshot {
  final List<ColonyMetrics> colonies;
  final int totalFoodOnMap;
  final int totalAnts;
  final double elapsedTime;
  final int daysPassed;
  final List<ThreatInfo> activeThreats;
  final List<RecentEvent> recentEvents;
  final Map<String, double> tunableParams;

  const HiveMindStateSnapshot({
    required this.colonies,
    required this.totalFoodOnMap,
    required this.totalAnts,
    required this.elapsedTime,
    required this.daysPassed,
    required this.activeThreats,
    required this.recentEvents,
    required this.tunableParams,
  });

  Map<String, dynamic> toJson() => {
        'colonies': colonies.map((c) => c.toJson()).toList(),
        'totalFoodOnMap': totalFoodOnMap,
        'totalAnts': totalAnts,
        'elapsedTime': elapsedTime.toStringAsFixed(1),
        'daysPassed': daysPassed,
        'activeThreats': activeThreats.map((t) => t.toJson()).toList(),
        'recentEvents': recentEvents.map((e) => e.toJson()).toList(),
        'tunableParams': tunableParams,
      };
}

/// Metrics for a single colony
class ColonyMetrics {
  final int colonyId;
  final String name; // Tribe name for AI context
  final int food;
  final int workers;
  final int soldiers;
  final int nurses;
  final int builders;
  final int larvae;
  final int eggs;
  final bool hasQueen;
  final bool underAttack;
  final double nestX;
  final double nestY;

  const ColonyMetrics({
    required this.colonyId,
    required this.name,
    required this.food,
    required this.workers,
    required this.soldiers,
    required this.nurses,
    required this.builders,
    required this.larvae,
    required this.eggs,
    required this.hasQueen,
    required this.underAttack,
    required this.nestX,
    required this.nestY,
  });

  int get totalAnts => workers + soldiers + nurses + builders + larvae + eggs;

  Map<String, dynamic> toJson() => {
        'colonyId': colonyId,
        'name': name,
        'food': food,
        'workers': workers,
        'soldiers': soldiers,
        'nurses': nurses,
        'builders': builders,
        'larvae': larvae,
        'eggs': eggs,
        'hasQueen': hasQueen,
        'underAttack': underAttack,
        'nestPosition': {'x': nestX.round(), 'y': nestY.round()},
      };
}

/// Information about an active threat
class ThreatInfo {
  final int targetColonyId;
  final int attackerColonyId;
  final double x;
  final double y;
  final int attackerCount;

  const ThreatInfo({
    required this.targetColonyId,
    required this.attackerColonyId,
    required this.x,
    required this.y,
    required this.attackerCount,
  });

  Map<String, dynamic> toJson() => {
        'targetColonyId': targetColonyId,
        'attackerColonyId': attackerColonyId,
        'position': {'x': x.round(), 'y': y.round()},
        'attackerCount': attackerCount,
      };
}

/// Recent significant event in the simulation
class RecentEvent {
  final String type; // 'food_found', 'battle', 'ant_died', 'room_built'
  final int colonyId;
  final String description;
  final double timestamp;

  const RecentEvent({
    required this.type,
    required this.colonyId,
    required this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'colonyId': colonyId,
        'description': description,
        'timestamp': timestamp.toStringAsFixed(1),
      };
}

/// AI decision response from the Hive Mind
class HiveMindDecision {
  final DateTime timestamp;
  final String reasoning;
  final List<ColonyDirective> directives;
  final String? suggestedMemory;

  const HiveMindDecision({
    required this.timestamp,
    required this.reasoning,
    required this.directives,
    this.suggestedMemory,
  });

  factory HiveMindDecision.fromJson(Map<String, dynamic> json) {
    return HiveMindDecision(
      timestamp: DateTime.now(),
      reasoning: json['reasoning'] as String? ?? 'No reasoning provided',
      directives: (json['directives'] as List<dynamic>?)
              ?.map((d) => ColonyDirective.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      suggestedMemory: json['suggestedMemory'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'reasoning': reasoning,
        'directives': directives.map((d) => d.toJson()).toList(),
        if (suggestedMemory != null) 'suggestedMemory': suggestedMemory,
      };
}

/// Types of directives the AI can issue
enum DirectiveType {
  adjustCasteRatio,
  setExplorerRatio,
  prioritizeDefense,
  focusOnFood,
  queueRoomConstruction,
  triggerEmergency,
}

/// A single directive from the AI to a colony
class ColonyDirective {
  final int colonyId;
  final DirectiveType type;
  final Map<String, dynamic> params;

  const ColonyDirective({
    required this.colonyId,
    required this.type,
    required this.params,
  });

  factory ColonyDirective.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'focusOnFood';
    DirectiveType type;
    try {
      type = DirectiveType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => DirectiveType.focusOnFood,
      );
    } catch (_) {
      type = DirectiveType.focusOnFood;
    }

    return ColonyDirective(
      colonyId: json['colonyId'] as int? ?? 0,
      type: type,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'colonyId': colonyId,
        'type': type.name,
        'params': params,
      };
}

/// Entry in the decision log for UI display
class HiveMindLogEntry {
  final DateTime timestamp;
  final HiveMindDecision decision;
  final bool wasApplied;

  const HiveMindLogEntry({
    required this.timestamp,
    required this.decision,
    this.wasApplied = true,
  });

  String get shortSummary {
    if (decision.directives.isEmpty) {
      return 'No action needed';
    }
    final types = decision.directives.map((d) => _directiveLabel(d.type)).toSet();
    return types.join(', ');
  }

  static String _directiveLabel(DirectiveType type) {
    switch (type) {
      case DirectiveType.adjustCasteRatio:
        return 'Adjust castes';
      case DirectiveType.setExplorerRatio:
        return 'Exploration';
      case DirectiveType.prioritizeDefense:
        return 'Defense';
      case DirectiveType.focusOnFood:
        return 'Food focus';
      case DirectiveType.queueRoomConstruction:
        return 'Build room';
      case DirectiveType.triggerEmergency:
        return 'Emergency';
    }
  }
}

/// Memory entry for vector storage
class ColonyMemory {
  final String sessionId;
  final int colonyId;
  final String category; // 'food_location', 'danger_zone', 'battle_outcome'
  final String content;
  final DateTime createdAt;

  const ColonyMemory({
    required this.sessionId,
    required this.colonyId,
    required this.category,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'colonyId': colonyId,
        'category': category,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };
}
