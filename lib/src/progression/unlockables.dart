/// Definition of an unlockable feature
class Unlockable {
  final String id;
  final String name;
  final String description;
  final int requiredLevel;

  const Unlockable({
    required this.id,
    required this.name,
    required this.description,
    required this.requiredLevel,
  });
}

/// All unlockable features in the game
/// Ordered by required level (full gating as requested)
const List<Unlockable> unlockables = [
  // Speed controls
  Unlockable(
    id: 'speed_2x',
    name: '2x Speed',
    description: 'Unlock 2x simulation speed',
    requiredLevel: 2,
  ),
  Unlockable(
    id: 'speed_3x',
    name: '3x Speed',
    description: 'Unlock 3x simulation speed',
    requiredLevel: 5,
  ),
  Unlockable(
    id: 'speed_5x',
    name: '5x Speed',
    description: 'Unlock 5x simulation speed',
    requiredLevel: 12,
  ),
  Unlockable(
    id: 'speed_10x',
    name: '10x Speed',
    description: 'Unlock maximum simulation speed',
    requiredLevel: 20,
  ),

  // Map sizes
  Unlockable(
    id: 'map_medium',
    name: 'Medium Map',
    description: 'Unlock medium-sized maps',
    requiredLevel: 3,
  ),
  Unlockable(
    id: 'map_large',
    name: 'Large Map',
    description: 'Unlock large maps',
    requiredLevel: 7,
  ),
  Unlockable(
    id: 'map_huge',
    name: 'Huge Map',
    description: 'Unlock the largest maps',
    requiredLevel: 20,
  ),

  // Colony counts
  Unlockable(
    id: 'colonies_2',
    name: '2 Colonies',
    description: 'Unlock 2-colony battles',
    requiredLevel: 4,
  ),
  Unlockable(
    id: 'colonies_3',
    name: '3 Colonies',
    description: 'Unlock 3-colony chaos',
    requiredLevel: 10,
  ),
  Unlockable(
    id: 'colonies_4',
    name: '4 Colonies',
    description: 'Unlock maximum colony wars',
    requiredLevel: 15,
  ),
];

/// Get all unlockables that should be unlocked at a given level
List<Unlockable> getUnlockablesForLevel(int level) {
  return unlockables.where((u) => u.requiredLevel <= level).toList();
}

/// Get the next unlockable after current level
Unlockable? getNextUnlockable(int level) {
  final sorted = unlockables.where((u) => u.requiredLevel > level).toList()
    ..sort((a, b) => a.requiredLevel.compareTo(b.requiredLevel));
  return sorted.isNotEmpty ? sorted.first : null;
}

/// Check if a feature ID is unlocked at a given level
bool isFeatureUnlocked(String featureId, int level) {
  final unlockable = unlockables.where((u) => u.id == featureId).firstOrNull;
  if (unlockable == null) return true; // Unknown features are always unlocked
  return level >= unlockable.requiredLevel;
}

/// Get max speed multiplier allowed at level
double getMaxSpeedForLevel(int level) {
  if (level >= 20) return 10.0;
  if (level >= 12) return 5.0;
  if (level >= 5) return 3.0;
  if (level >= 2) return 2.0;
  return 1.0;
}

/// Get max colonies allowed at level
int getMaxColoniesForLevel(int level) {
  if (level >= 15) return 4;
  if (level >= 10) return 3;
  if (level >= 4) return 2;
  return 1;
}

/// Get available map sizes at level
List<String> getAvailableMapSizesForLevel(int level) {
  final sizes = <String>['Small'];
  if (level >= 3) sizes.add('Medium');
  if (level >= 7) sizes.add('Large');
  if (level >= 20) sizes.add('Huge');
  return sizes;
}
