/// Random tribe-like names for ant colonies
library;

import 'dart:math';

/// 100 tribe-sounding names for ant colonies
const List<String> _tribeNames = [
  // Ancient/Mystical
  'Zephyra', 'Thornveil', 'Ashborne', 'Grimhold', 'Shadowmire',
  'Ironmaw', 'Stormclaw', 'Duskfang', 'Nighthollow', 'Embercrest',
  'Frostbite', 'Bonechill', 'Darkthorn', 'Wraithwood', 'Voidwalker',
  'Skullcrusher', 'Bloodstone', 'Deathwhisper', 'Soulrender', 'Doomclaw',

  // Nature-inspired
  'Oakroot', 'Mossback', 'Fernglade', 'Willowshade', 'Briarthorn',
  'Stonebark', 'Deepburrow', 'Mudcrawler', 'Sandskitter', 'Leafcutter',
  'Rootweaver', 'Tunnelkin', 'Earthmover', 'Rockgnaw', 'Claywarden',
  'Dustwalker', 'Pebbleback', 'Soilborn', 'Dirtdelver', 'Groundling',

  // Warrior tribes
  'Razorfang', 'Warborn', 'Battleswarm', 'Siegebreaker', 'Shieldwall',
  'Bladerunner', 'Spearhead', 'Vanguard', 'Ironlegion', 'Steelclaw',
  'Warcry', 'Bloodmarch', 'Deathswarm', 'Ravager', 'Destroyer',
  'Conqueror', 'Vanquisher', 'Slayer', 'Berserker', 'Marauder',

  // Mystical/Elemental
  'Sunfire', 'Moonshade', 'Starfall', 'Skyrender', 'Cloudpiercer',
  'Flameheart', 'Icevein', 'Thunderclap', 'Windrunner', 'Earthshaker',
  'Tidecaller', 'Stormborn', 'Fireforged', 'Frostweaver', 'Shadowcaster',
  'Lightbringer', 'Darkbinder', 'Spiritwalker', 'Soulkeeper', 'Dreamweaver',

  // Ancient civilizations
  'Azurak', 'Korthun', 'Velmar', 'Draxon', 'Zenthar',
  'Mythros', 'Pyraxis', 'Nethrim', 'Solarak', 'Lunaris',
  'Terrax', 'Aquilon', 'Ignitus', 'Glacius', 'Tempestus',
  'Umbral', 'Radiant', 'Nocturne', 'Aurora', 'Eclipse',

  // Descriptive tribes
  'Swiftmarch', 'Silentfoot', 'Quicktunnel', 'Hardhive', 'Deepnest',
  'Highcolony', 'Oldguard', 'Newblood', 'Firstborn', 'Laststand',
  'Everlast', 'Neverfall', 'Ironwill', 'Truepath', 'Stronghold',
  'Blackmound', 'Redearth', 'Whitesand', 'Greyveil', 'Goldmandible',

  // Compound names
  'Mandiblecrusher', 'Antennaseer', 'Chitinbreaker', 'Formicida', 'Myrmex',
  'Hexapod', 'Colonarch', 'Queensguard', 'Hivemind', 'Swarmfather',
];

/// Get a random tribe name using the given random instance
String getRandomTribeName(Random random) {
  return _tribeNames[random.nextInt(_tribeNames.length)];
}

/// Get unique tribe names for multiple colonies
List<String> getUniqueTribeNames(int count, int seed) {
  final random = Random(seed);
  final shuffled = List<String>.from(_tribeNames)..shuffle(random);
  return shuffled.take(count).toList();
}

/// Colony name manager - stores assigned names per session
class ColonyNameManager {
  ColonyNameManager._();
  static final instance = ColonyNameManager._();

  final Map<int, String> _colonyNames = {};
  int? _lastSeed;

  /// Initialize colony names for a game session
  void initializeNames(int colonyCount, int seed) {
    if (_lastSeed == seed && _colonyNames.length >= colonyCount) {
      return; // Already initialized with same seed
    }

    _lastSeed = seed;
    _colonyNames.clear();

    final names = getUniqueTribeNames(colonyCount, seed);
    for (int i = 0; i < names.length; i++) {
      _colonyNames[i] = names[i];
    }
  }

  /// Get name for a colony (falls back to "Colony X" if not initialized)
  String getName(int colonyId) {
    return _colonyNames[colonyId] ?? 'Colony $colonyId';
  }

  /// Get all assigned names
  Map<int, String> get allNames => Map.unmodifiable(_colonyNames);

  /// Reset names (call on new game)
  void reset() {
    _colonyNames.clear();
    _lastSeed = null;
  }
}
