# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AntWorld is a Flutter + Flame game that simulates ant colonies using emergent behavior and pheromone-based navigation. Individual ants follow simple rules (sense pheromones with 3 sensors, move toward stronger signals, drop pheromones, pick up food) which creates complex colony-wide patterns like foraging highways.

The simulation supports multiple competing colonies (up to 4), ant castes (worker, soldier, nurse, drone, princess, queen, larva, egg, builder), and combat between colonies.

## Common Development Commands

### Running and Testing
```bash
# Install dependencies
flutter pub get

# Run the app (defaults to available device)
flutter run

# Run on specific platforms
flutter run -d chrome           # Web
flutter run -d macos            # macOS
flutter run -d ios              # iOS (requires Xcode)
flutter run -d windows          # Windows
flutter run -d linux            # Linux

# Build release
flutter build web               # For web deployment
flutter build macos             # For macOS app
flutter build windows           # For Windows app
flutter build linux             # For Linux app

# Run tests
flutter test

# Analyze code
flutter analyze
```

### Icon Generation
```bash
# After modifying assets/icons/icon.png
flutter pub run flutter_launcher_icons
```

## Architecture Overview

### Core System Flow

The app follows a game loop architecture where `AntWorldGame` (Flame) handles rendering and input, while `ColonySimulation` manages the simulation logic:

```
main.dart
  └─> AntWorldApp (Flutter widget tree)
      ├─> GameWidget(AntWorldGame) - Flame game engine
      │   ├─> Rendering (60fps)
      │   └─> Input handling
      └─> AntHud (Flutter overlay) - UI controls

AntWorldGame
  └─> ColonySimulation.update(dt)
      ├─> WorldGrid.decay() - Pheromone decay
      └─> For each Ant:
          ├─> Sense pheromones (3 sensors)
          ├─> Decide steering direction
          ├─> Move forward
          ├─> Drop pheromones
          └─> Check food pickup/delivery
```

### Key Components

**`ColonySimulation`** (`lib/src/simulation/colony_simulation.dart`)
- Orchestrates the entire simulation update loop
- Manages ant list and spawning for multiple colonies (up to 4)
- Tracks food per colony with separate ValueNotifiers (colony0Food, colony1Food)
- Coordinates between ants and world grid
- Combat resolution between colonies with spatial hashing for O(n) performance
- Automatic food replenishment to maintain minimum supply
- Caches ant statistics per caste and colony for O(1) UI access
- **Defense System**: Detects enemy ants within 12 cells of nest, triggers defense alerts (5s duration), assigns attack targets to soldiers
- **Room Management**: Tracks room occupancy, triggers expansion when over capacity (checked every 30s)
- **Princess Breeding**: Queens spawn princesses after 75 food threshold (max 2 per colony), automatic succession on queen death
- **Smart Queen Guidance**: Queens use BFS pathfinding to compute walkable paths to food and deposit pheromones along routes
- ValueNotifiers expose state to UI (antCount, foodCollected, daysPassed, elapsedTime, pheromonesVisible, foodScentVisible, foodPheromonesVisible, homePheromonesVisible, antSpeedMultiplier, paused)
- Tracks death events for visual effects (DeathEvent list with position, colonyId, timestamp)

**`WorldGrid`** (`lib/src/simulation/world_grid.dart`)
- 2D grid storing cell types (air, dirt, food, rock) with corresponding health values
- Dirt has variable hardness via DirtType enum (softSand, looseSoil, packedEarth, clay, hardite, bedrock)
- **Per-colony pheromone layers**: `foodPheromones0/1`, `homePheromones0/1` with ownership tracking
- Pheromone decay happens every frame (only active cells tracked via `_activePheromoneCells` Set)
- **Food scent diffusion**: BFS-based scent spreading every 10 frames with `_activeFoodScentCells` dirty set
- Food positions cached in a Set for O(1) lookup
- BFS pathfinding via `_homeDistances` array for returning ants (per-colony)
- **Room System**: `RoomType` enum (home, nursery, foodStorage, barracks) with `Room` class tracking capacity and occupancy
- `computePathToFood()` provides BFS pathfinding for queen guidance
- Grid indices calculated as: `index(x, y) = y * cols + x`

**`WorldGenerator`** (`lib/src/simulation/world_generator.dart`)
- Procedural world generation with seeded randomness
- Generates tunnels, rooms (hatchery, nursery, food storage, barracks), and initial food placement
- Creates colony-specific room layouts with appropriate capacities

**`Ant`** (`lib/src/simulation/ant.dart`)
- Individual ant with position, angle, energy, colonyId, caste
- Castes: worker, soldier, nurse, drone, princess, queen, larva, egg, builder (AntCaste enum)
- CasteStats provides per-caste speedMultiplier, HP, attack, defense, aggression
- State machine: foraging → finds food → returns home → delivers food → repeats
- 3-sensor system for pheromone detection (left, front, right at ±0.6 radians)
- Direct food sensing within 30 cells when not following pheromone trails
- Grid pathfinding (BFS) guides ants home via `WorldGrid.directionToNest()`
- **Food delivery**: Workers deliver to food storage room instead of nest center
- Energy system: drains while moving, recovers while resting, digging costs extra
- Combat stats: attack, defense, HP for fighting ants from other colonies
- Explorer ants (5% by default) ignore pheromones more often to discover new food
- **Queen mechanics**: Produces eggs every 45s, uses BFS pathfinding for food guidance
- **Princess mechanics**: High HP (300), slow movement (0.4x), auto-promotes to queen on succession
- **Soldier patrol**: Maintains position within nest radius (0.5x inner, 2x outer), defense mode with 1.3x speed boost and 50% damage bonus
- **Egg/Larva lifecycle**: Eggs hatch after 20s (`_growthProgress`), larvae mature after 60s into adult caste
- Nurses care for larvae, soldiers patrol and defend with attack targets from defense system
- Builders have BuilderTask enum: idle, buildingRoom, reinforcingWall, emergencyDefense, returningHome

**`AntWorldGame`** (`lib/src/game/ant_world_game.dart`)
- Flame game component that renders the simulation
- Caches static terrain in a Picture object for performance
- **LOD rendering**: Simple dot (< 5px), medium (< 8px), full detail with legs/antennae
- **Colony-colored pheromones**: Uses `bodyColorForColony()` to colorize trails per colony
- **Death pop effects**: Expanding circles with fade animation (0.35s duration)
- **Viewport culling**: Skip rendering elements outside visible bounds
- **Pheromone caching**: Updates rendering only every 3 frames
- Handles mouse/touch input for digging and placing food/rocks
- Keyboard shortcuts (P for pheromone toggle)
- Manages brush modes (dig, food, rock)
- **Frame telemetry**: Logs average update time and FPS every 5 seconds

**`SimulationConfig`** (`lib/src/simulation/simulation_config.dart`)
- Immutable configuration object with all tunable parameters
- Includes grid size, ant behavior, pheromone strengths, energy settings, etc.
- Use `config.copyWith()` to create variations for testing

**`SimulationStorage`** (`lib/src/state/simulation_storage.dart`)
- Persists world state to local storage using shared_preferences
- Saves/restores: grid state, pheromones, ants, config, food count
- Automatically restores on app launch

**`AnalyticsService`** (`lib/src/services/analytics_service.dart`)
- Singleton service for Firebase Analytics tracking
- Tracks game events: game_start, game_load, map_generated, colony_takeover
- Tracks milestones: food_milestone, day_milestone
- Tracks user actions: speed_changed, brush_used, game_saved

### Data Structures

**Grid Storage**: Single flat `Uint8List` for cells, indexed by `y * cols + x`
- Cell types: air (0), dirt (1), food (2), rock (3)
- Dirt types with varying HP: softSand (5), looseSoil (12), packedEarth (25), clay (50), hardite (100), bedrock (200)
- Separate `Float32List` for dirt health values
- Separate `Float32List` arrays for each pheromone type

**Pheromone System**: Per-colony pheromone overlays
- Food pheromones: deposited by ants carrying food (strength 0.5), colored per colony
- Home pheromones: deposited by foraging ants (strength 0.2), colored per colony
- Separate layers per colony: `foodPheromones0/1`, `homePheromones0/1`
- `foodPheromoneOwner0/1` tracks which colony deposited each pheromone
- Ants only sense their own colony's pheromones
- Nest center always has max home pheromone (1.0)
- Decay factor: 0.985 per frame (configurable)
- **Food scent**: Separate BFS-based diffusion from food cells, spreads 0.97x per cell distance

**Ant Sensing**: 3 sensors reach out from ant's position
- Each sensor is 6 cells away (configurable)
- Left/right sensors at ±0.6 radians from current angle
- Returns accumulated pheromone strength along the sensor ray
- Actual food cells get +10 bonus signal for direct detection
- Perceptual noise (±15% variation) makes trails spread naturally

**Return Pathfinding**: BFS from nest precomputes distances
- `WorldGrid._homeDistances` stores shortest walkable distance to nest
- `directionToNest()` returns vector toward neighbor with lower distance
- Recomputed when terrain changes (`_homeDistanceDirty` flag)
- Ants returning home use this instead of pheromone following

**Room System**: Specialized colony rooms
- `RoomType.home` (Hatchery): Queen's chamber, capacity 5, cannot expand
- `RoomType.nursery`: Egg/larva care, capacity 20, expands when over capacity
- `RoomType.foodStorage`: Food stockpile, capacity 100, visual golden spiral pattern for food items
- `RoomType.barracks`: Worker/soldier rest area, capacity 15, expands when over capacity
- Room occupancy checked every 30 seconds, triggers builder tasks when over 120% capacity
- `_assignRestLocation()` selects barracks over nest center for resting ants

**Defense System**: Colony threat response
- `_defenseAlertRadius` (12 cells): Detection range around nest
- `_defenseAlertPositions`: Stores threat location per colony
- `_defenseAlertTimers`: Alert duration (5 seconds)
- Soldiers receive attack targets via `getDefenseTarget(colonyId)`
- **Defending soldiers**: 1.3x speed, 50% damage boost, aggression = 1.0
- Emergency builder tasks: Construct defensive walls between nest and threat

**Combat System**: Inter-colony combat
- Combat triggers when ants from different colonies are within proximity
- Spatial hashing enables O(n) collision detection instead of O(n²)
- Damage = `attacker.attack * variance - defender.defense * mitigation`
- Dead ants are removed, death events queued for visual effects
- Colony takeover events tracked via AnalyticsService

**Princess/Breeding System**: Colony succession
- Queens lay eggs every 45 seconds (`_eggLayInterval`)
- Eggs hatch after 20 seconds, larvae mature after 60 seconds
- Princess threshold: 75 food units (`_foodForPrincess`)
- Max 2 princesses per colony (`_maxPrincessesPerColony`)
- Princess stats: 300 HP, 0.4x speed, no combat aggression
- Automatic succession: Princess promotes to queen when current queen dies

## Code Patterns

### Adding New Simulation Features

When extending the simulation, follow this pattern:

1. **Add config parameter** to `SimulationConfig` if tunable
2. **Update data structure** in `WorldGrid` or `Ant` as needed
3. **Implement logic** in the appropriate update method
4. **Add rendering** in `AntWorldGame._drawXXX()` methods
5. **Expose to UI** via ValueNotifier if user-facing
6. **Add save/restore** support in `SimulationStorage` if persistent

### Working with the Grid

```dart
// Always check bounds before accessing
if (!world.isInsideIndex(x, y)) return;

// Get cell type
final cellType = world.cellTypeAt(x, y);

// Modify cells
world.setCell(x, y, CellType.air);

// Access pheromones
final foodScent = world.foodPheromoneAt(x, y);
world.depositFoodPheromone(x, y, 0.5);
```

### Performance Considerations

- Static terrain is cached in a `Picture` - call `game.invalidateTerrainLayer()` after terrain changes
- Delta time is clamped to 0.05s max to prevent physics instability during lag
- Pheromone decay only processes active cells tracked in `_activePheromoneCells` Set
- Food positions stored in `Set<int>` for fast collision detection
- BFS pathfinding is lazy-computed and cached until terrain changes
- **LOD rendering**: Ants render as dots (< 5px), simplified (< 8px), or full detail based on zoom
- **Viewport culling**: Skip rendering ants and death effects outside visible bounds
- **Pheromone caching**: Pheromone rendering updates every 3 frames, not every frame
- **Food scent dirty sets**: `_activeFoodScentCells` tracks only cells with active scent for efficient iteration
- **Spatial hashing**: Combat and separation calculations use O(n) spatial hashing instead of O(n²)
- **Frame telemetry**: `FrameTelemetry` class logs average update time and FPS every 5 seconds

### State Management

The app uses Flutter's `ValueNotifier` for reactive UI updates:
- `antCount`, `foodCollected`, `daysPassed` - stats displayed in HUD
- `pheromonesVisible` - toggled by user, affects rendering
- `antSpeedMultiplier` - user-controlled speed (0.2x - 3.0x)

All simulation state is in `ColonySimulation`, game state is in `AntWorldGame`, UI state is in `AntHud`.

## Testing Notes

- World generation is deterministic when using `generateRandomWorld(seed: N)`
- `ColonySimulation._lastSeed` stores the seed used for the current world
- Focus tests on: ant state transitions, pheromone decay math, collision detection, energy system, combat resolution
- UI tests should verify ValueNotifier updates trigger proper rebuilds

## Common Gotchas

- **Grid coordinates vs pixel coordinates**: Grid uses integer (col, row), rendering uses float (x, y) in pixels. Convert with `cellPos * config.cellSize`.
- **Angle wrapping**: Ant angles are in radians, not normalized. Use `atan2(dy, dx)` for direction calculations. Use `_normalizeAngle()` helper in Ant class.
- **Pheromone indexing**: Always use `world.index(x, y)` rather than calculating manually to avoid bugs.
- **Delta time**: `dt` is in seconds. Speed values are typically "per second" so multiply by `dt` when applying.
- **Energy precision**: Energy uses double for smooth recovery but display rounds. Keep energy <= capacity.
- **Terrain caching**: After bulk terrain edits, call `game.invalidateTerrainLayer()` once rather than per cell.
- **Pathfinding invalidation**: Terrain changes auto-set `_homeDistanceDirty = true`, but call `world.markHomeDistancesDirty()` if modifying terrain directly.
- **Collision detection**: Ant movement uses Amanatides & Woo raycast algorithm in `_checkPathCollision()` to detect obstacles along the path.

## Architecture Philosophy

This codebase follows a clear separation between:
- **Simulation logic** (lib/src/simulation/) - Pure Dart, no rendering
- **Game engine** (lib/src/game/) - Flame integration, rendering, input, death effects
- **UI layer** (lib/src/ui/) - Flutter widgets, overlays (includes AntHud and AntGalleryPage)
- **Visuals** (lib/src/visuals/) - Ant sprite rendering with LOD levels and visual components
- **Persistence** (lib/src/state/) - Save/load functionality
- **Services** (lib/src/services/) - Firebase analytics and other services

The simulation can run headless for testing. The game layer is a thin rendering wrapper with LOD optimization. The UI is stateless and driven by ValueNotifiers from the simulation.

## Firebase Setup

Firebase Analytics is configured for iOS, Android, macOS, and web. Firebase options are in `lib/firebase_options.dart` (generated by FlutterFire CLI). The `AnalyticsService` singleton handles all event tracking.
