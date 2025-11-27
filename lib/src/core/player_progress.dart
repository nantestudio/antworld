class LevelResult {
  const LevelResult({
    this.stars = 0,
    this.completed = false,
    this.bestTime = Duration.zero,
    this.lastScore = 0,
  });

  final int stars;
  final bool completed;
  final Duration bestTime;
  final int lastScore;

  Map<String, dynamic> toJson() {
    return {
      'stars': stars,
      'completed': completed,
      'bestTime': bestTime.inSeconds,
      'lastScore': lastScore,
    };
  }

  factory LevelResult.fromJson(Map<String, dynamic> json) {
    final seconds = json['bestTime'] as int? ?? 0;
    return LevelResult(
      stars: json['stars'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      bestTime: Duration(seconds: seconds),
      lastScore: json['lastScore'] as int? ?? 0,
    );
  }
}

class DailyGoalProgress {
  const DailyGoalProgress({
    required this.dayId,
    this.completedGoalIds = const <String>{},
    this.totalGoals = 0,
  });

  final String dayId;
  final Set<String> completedGoalIds;
  final int totalGoals;

  Map<String, dynamic> toJson() {
    return {
      'dayId': dayId,
      'completedGoalIds': completedGoalIds.toList(),
      'totalGoals': totalGoals,
    };
  }

  factory DailyGoalProgress.fromJson(Map<String, dynamic> json) {
    final completed = (json['completedGoalIds'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .toSet();
    return DailyGoalProgress(
      dayId: json['dayId'] as String? ?? '',
      completedGoalIds: completed,
      totalGoals: json['totalGoals'] as int? ?? 0,
    );
  }
}

class EquippedCosmetics {
  const EquippedCosmetics({
    this.body = 'default',
    this.trail = 'default',
    this.badge,
  });

  final String body;
  final String trail;
  final String? badge;

  Map<String, dynamic> toJson() {
    return {'body': body, 'trail': trail, 'badge': badge};
  }

  factory EquippedCosmetics.fromJson(Map<String, dynamic> json) {
    return EquippedCosmetics(
      body: json['body'] as String? ?? 'default',
      trail: json['trail'] as String? ?? 'default',
      badge: json['badge'] as String?,
    );
  }
}

class PlayerProgress {
  const PlayerProgress({
    this.totalXp = 0,
    this.level = 1,
    this.unlockedMilestones = const <String>{},
    this.unlockedAchievements = const <String>{},
    this.campaignProgress = const <String, LevelResult>{},
    this.totalStars = 0,
    this.todayGoals,
    this.currentStreak = 0,
    this.unlockedCosmetics = const <String>{},
    this.equipped = const EquippedCosmetics(),
    this.totalFoodCollected = 0,
    this.totalAntsHatched = 0,
    this.totalDaysPlayed = 0,
    this.totalPlayTime = Duration.zero,
  });

  final int totalXp;
  final int level;
  final Set<String> unlockedMilestones;
  final Set<String> unlockedAchievements;
  final Map<String, LevelResult> campaignProgress;
  final int totalStars;
  final DailyGoalProgress? todayGoals;
  final int currentStreak;
  final Set<String> unlockedCosmetics;
  final EquippedCosmetics equipped;
  final int totalFoodCollected;
  final int totalAntsHatched;
  final int totalDaysPlayed;
  final Duration totalPlayTime;

  static PlayerProgress initial() => const PlayerProgress();

  PlayerProgress copyWith({
    int? totalXp,
    int? level,
    Set<String>? unlockedMilestones,
    Set<String>? unlockedAchievements,
    Map<String, LevelResult>? campaignProgress,
    int? totalStars,
    DailyGoalProgress? todayGoals,
    int? currentStreak,
    Set<String>? unlockedCosmetics,
    EquippedCosmetics? equipped,
    int? totalFoodCollected,
    int? totalAntsHatched,
    int? totalDaysPlayed,
    Duration? totalPlayTime,
  }) {
    return PlayerProgress(
      totalXp: totalXp ?? this.totalXp,
      level: level ?? this.level,
      unlockedMilestones: unlockedMilestones ?? this.unlockedMilestones,
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
      campaignProgress: campaignProgress ?? this.campaignProgress,
      totalStars: totalStars ?? this.totalStars,
      todayGoals: todayGoals ?? this.todayGoals,
      currentStreak: currentStreak ?? this.currentStreak,
      unlockedCosmetics: unlockedCosmetics ?? this.unlockedCosmetics,
      equipped: equipped ?? this.equipped,
      totalFoodCollected: totalFoodCollected ?? this.totalFoodCollected,
      totalAntsHatched: totalAntsHatched ?? this.totalAntsHatched,
      totalDaysPlayed: totalDaysPlayed ?? this.totalDaysPlayed,
      totalPlayTime: totalPlayTime ?? this.totalPlayTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalXp': totalXp,
      'level': level,
      'unlockedMilestones': unlockedMilestones.toList(),
      'unlockedAchievements': unlockedAchievements.toList(),
      'campaignProgress': campaignProgress.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'totalStars': totalStars,
      'todayGoals': todayGoals?.toJson(),
      'currentStreak': currentStreak,
      'unlockedCosmetics': unlockedCosmetics.toList(),
      'equipped': equipped.toJson(),
      'totalFoodCollected': totalFoodCollected,
      'totalAntsHatched': totalAntsHatched,
      'totalDaysPlayed': totalDaysPlayed,
      'totalPlayTime': totalPlayTime.inSeconds,
    };
  }

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    final campaignData =
        (json['campaignProgress'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return PlayerProgress(
      totalXp: json['totalXp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      unlockedMilestones: ((json['unlockedMilestones'] as List<dynamic>?) ?? [])
          .map((value) => value.toString())
          .toSet(),
      unlockedAchievements:
          ((json['unlockedAchievements'] as List<dynamic>?) ?? [])
              .map((value) => value.toString())
              .toSet(),
      campaignProgress: campaignData.map(
        (key, value) => MapEntry(
          key,
          LevelResult.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        ),
      ),
      totalStars: json['totalStars'] as int? ?? 0,
      todayGoals: (json['todayGoals'] as Map<String, dynamic>?) != null
          ? DailyGoalProgress.fromJson(
              Map<String, dynamic>.from(
                json['todayGoals'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
      currentStreak: json['currentStreak'] as int? ?? 0,
      unlockedCosmetics: ((json['unlockedCosmetics'] as List<dynamic>?) ?? [])
          .map((value) => value.toString())
          .toSet(),
      equipped: json['equipped'] != null
          ? EquippedCosmetics.fromJson(
              Map<String, dynamic>.from(
                json['equipped'] as Map<dynamic, dynamic>,
              ),
            )
          : const EquippedCosmetics(),
      totalFoodCollected: json['totalFoodCollected'] as int? ?? 0,
      totalAntsHatched: json['totalAntsHatched'] as int? ?? 0,
      totalDaysPlayed: json['totalDaysPlayed'] as int? ?? 0,
      totalPlayTime: Duration(seconds: json['totalPlayTime'] as int? ?? 0),
    );
  }
}
