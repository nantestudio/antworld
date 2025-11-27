/// Immutable state for player progression
class ProgressionState {
  final int totalXP;
  final int level;
  final Set<String> unlockedAchievements;
  final Set<String> unlockedFeatures;
  final Map<String, int> lifetimeStats;

  const ProgressionState({
    this.totalXP = 0,
    this.level = 1,
    this.unlockedAchievements = const {},
    this.unlockedFeatures = const {},
    this.lifetimeStats = const {},
  });

  /// XP required to reach the next level
  /// Level 1->2: 150 XP, Level 2->3: 250 XP, etc.
  int get xpForNextLevel => level * 100 + 50;

  /// XP accumulated towards next level
  int get xpProgress {
    int xpUsed = 0;
    for (int l = 1; l < level; l++) {
      xpUsed += l * 100 + 50;
    }
    return totalXP - xpUsed;
  }

  /// Progress towards next level (0.0 - 1.0)
  double get levelProgress => xpProgress / xpForNextLevel;

  ProgressionState copyWith({
    int? totalXP,
    int? level,
    Set<String>? unlockedAchievements,
    Set<String>? unlockedFeatures,
    Map<String, int>? lifetimeStats,
  }) {
    return ProgressionState(
      totalXP: totalXP ?? this.totalXP,
      level: level ?? this.level,
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
      unlockedFeatures: unlockedFeatures ?? this.unlockedFeatures,
      lifetimeStats: lifetimeStats ?? this.lifetimeStats,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalXP': totalXP,
      'level': level,
      'unlockedAchievements': unlockedAchievements.toList(),
      'unlockedFeatures': unlockedFeatures.toList(),
      'lifetimeStats': lifetimeStats,
    };
  }

  factory ProgressionState.fromJson(Map<String, dynamic> json) {
    return ProgressionState(
      totalXP: json['totalXP'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      unlockedAchievements:
          (json['unlockedAchievements'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      unlockedFeatures:
          (json['unlockedFeatures'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      lifetimeStats:
          (json['lifetimeStats'] as Map<String, dynamic>?)?.cast<String, int>() ?? {},
    );
  }
}
