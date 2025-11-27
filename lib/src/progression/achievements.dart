import '../simulation/colony_simulation.dart';
import 'progression_state.dart';

/// Definition of an achievement
class Achievement {
  final String id;
  final String name;
  final String description;
  final int xpReward;
  final bool Function(ProgressionState state, ColonySimulation sim)? checkCondition;
  final bool isOneTime; // Only awarded once ever

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.xpReward,
    this.checkCondition,
    this.isOneTime = true,
  });
}

/// All achievements in the game
final List<Achievement> achievements = [
  // Food milestones
  Achievement(
    id: 'first_food',
    name: 'First Harvest',
    description: 'Collect your first 10 food',
    xpReward: 10,
    checkCondition: (state, sim) => sim.foodCollected.value >= 10,
  ),
  Achievement(
    id: 'food_100',
    name: 'Food Hoarder',
    description: 'Collect 100 food in a single game',
    xpReward: 25,
    checkCondition: (state, sim) => sim.foodCollected.value >= 100,
  ),
  Achievement(
    id: 'food_500',
    name: 'Food Baron',
    description: 'Collect 500 food in a single game',
    xpReward: 50,
    checkCondition: (state, sim) => sim.foodCollected.value >= 500,
  ),
  Achievement(
    id: 'food_1000',
    name: 'Food Empire',
    description: 'Collect 1000 food in a single game',
    xpReward: 100,
    checkCondition: (state, sim) => sim.foodCollected.value >= 1000,
  ),

  // Day milestones
  Achievement(
    id: 'survive_5_days',
    name: 'New Colony',
    description: 'Survive 5 days',
    xpReward: 15,
    checkCondition: (state, sim) => sim.daysPassed.value >= 5,
  ),
  Achievement(
    id: 'survive_10_days',
    name: 'Survivor',
    description: 'Survive 10 days',
    xpReward: 30,
    checkCondition: (state, sim) => sim.daysPassed.value >= 10,
  ),
  Achievement(
    id: 'survive_30_days',
    name: 'Veteran Colony',
    description: 'Survive 30 days',
    xpReward: 75,
    checkCondition: (state, sim) => sim.daysPassed.value >= 30,
  ),

  // Ant population
  Achievement(
    id: 'ants_100',
    name: 'Growing Colony',
    description: 'Have 100 ants at once',
    xpReward: 20,
    checkCondition: (state, sim) => sim.ants.length >= 100,
  ),
  Achievement(
    id: 'ants_500',
    name: 'Army Builder',
    description: 'Have 500 ants at once',
    xpReward: 50,
    checkCondition: (state, sim) => sim.ants.length >= 500,
  ),
  Achievement(
    id: 'ants_1000',
    name: 'Mega Colony',
    description: 'Have 1000 ants at once',
    xpReward: 100,
    checkCondition: (state, sim) => sim.ants.length >= 1000,
  ),

  // Combat achievements (triggered via events, not conditions)
  const Achievement(
    id: 'first_battle',
    name: 'First Blood',
    description: 'Win your first colony battle',
    xpReward: 30,
    checkCondition: null, // Triggered manually
  ),
  const Achievement(
    id: 'conqueror',
    name: 'Conqueror',
    description: 'Defeat 3 enemy colonies total',
    xpReward: 100,
    checkCondition: null, // Triggered manually based on lifetime stats
  ),

  // Lifetime achievements (based on lifetimeStats)
  Achievement(
    id: 'lifetime_food_5000',
    name: 'Master Forager',
    description: 'Collect 5000 food total across all games',
    xpReward: 150,
    checkCondition: (state, sim) =>
        (state.lifetimeStats['total_food'] ?? 0) + sim.foodCollected.value >= 5000,
  ),
  Achievement(
    id: 'lifetime_games_10',
    name: 'Dedicated',
    description: 'Play 10 games',
    xpReward: 50,
    checkCondition: (state, sim) => (state.lifetimeStats['games_played'] ?? 0) >= 10,
  ),
];

/// Get achievement by ID
Achievement? getAchievementById(String id) {
  return achievements.where((a) => a.id == id).firstOrNull;
}

/// Check all achievements and return newly unlocked ones
List<Achievement> checkAchievements(ProgressionState state, ColonySimulation sim) {
  final newlyUnlocked = <Achievement>[];

  for (final achievement in achievements) {
    // Skip already unlocked
    if (state.unlockedAchievements.contains(achievement.id)) continue;

    // Skip achievements without auto-check conditions
    if (achievement.checkCondition == null) continue;

    // Check condition
    if (achievement.checkCondition!(state, sim)) {
      newlyUnlocked.add(achievement);
    }
  }

  return newlyUnlocked;
}
