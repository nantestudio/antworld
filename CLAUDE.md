# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AntWorld is a Flutter + Flame game that simulates an ant colony using emergent behavior and pheromone-based navigation. Individual ants follow simple rules (sense pheromones with 3 sensors, move toward stronger signals, drop pheromones, pick up food) which creates complex colony-wide patterns like foraging highways.

The simulation includes combat mechanics where enemy ant raids periodically spawn and attack the colony.

## Common Development Commands

### Running and Testing
```bash
# Install dependencies
flutter pub get

# Run the app (defaults to available device)
flutter run

# Run on specific platforms
flutter run -d chrome          # Web
flutter run -d macos            # macOS
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
- Manages ant list and spawning, including enemy ants
- Tracks food collected and day counter
- Coordinates between ants and world grid
- Handles enemy raids (periodic spawning from map edges)
- Combat resolution between friendly and enemy ants
- Automatic food replenishment to maintain minimum supply
- ValueNotifiers expose state to UI (antCount, foodCollected, daysPassed, pheromonesVisible, antSpeedMultiplier)

**`WorldGrid`** (`lib/src/simulation/world_grid.dart`)
- 2D grid storing cell types (air, dirt, food, rock) with corresponding health values
- Two Float32List arrays for pheromone layers (food pheromones, home pheromones)
- Pheromone decay happens every frame (only active cells tracked for efficiency)
- Food positions cached in a Set for O(1) lookup
- BFS pathfinding via `_homeDistances` array for returning ants
- Grid indices calculated as: `index(x, y) = y * cols + x`

**`WorldGenerator`** (`lib/src/simulation/world_generator.dart`)
- Procedural world generation with seeded randomness
- Generates tunnels, rooms, and initial food placement

**`Ant`** (`lib/src/simulation/ant.dart`)
- Individual ant with position, angle, energy, state (forage/returnHome/rest)
- State machine: foraging → finds food → returns home → delivers food → repeats
- 3-sensor system for pheromone detection (left, front, right at ±0.6 radians)
- Direct food sensing within 30 cells when not following pheromone trails
- Grid pathfinding (BFS) guides ants home via `WorldGrid.directionToNest()`
- Energy system: drains while moving, recovers while resting, digging costs extra
- Combat stats: attack, defense, HP for fighting enemy ants
- Explorer ants (5% by default) ignore pheromones more often to discover new food

**`AntWorldGame`** (`lib/src/game/ant_world_game.dart`)
- Flame game component that renders the simulation
- Caches static terrain in a Picture object for performance
- Handles mouse/touch input for digging and placing food/rocks
- Keyboard shortcuts (P for pheromone toggle)
- Manages brush modes (dig, food, rock)

**`SimulationConfig`** (`lib/src/simulation/simulation_config.dart`)
- Immutable configuration object with all tunable parameters
- Includes grid size, ant behavior, pheromone strengths, energy settings, etc.
- Use `config.copyWith()` to create variations for testing

**`SimulationStorage`** (`lib/src/state/simulation_storage.dart`)
- Persists world state to local storage using shared_preferences
- Saves/restores: grid state, pheromones, ants, config, food count
- Automatically restores on app launch

### Data Structures

**Grid Storage**: Single flat `Uint8List` for cells, indexed by `y * cols + x`
- Cell types: air (0), dirt (1), food (2), rock (3)
- Separate `Float32List` for dirt health values
- Separate `Float32List` arrays for each pheromone type

**Pheromone System**: Two separate overlays on the grid
- Food pheromones (blue): deposited by ants carrying food (strength 0.5)
- Home pheromones (gray): deposited by foraging ants (strength 0.2)
- Nest center always has max home pheromone (1.0)
- Decay factor: 0.985 per frame (configurable)

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

**Combat System**: Enemy raids attack the colony
- Raids spawn periodically (35-75 seconds) from random map edges
- Enemy count scales with colony size (1-20% of friendly ants)
- Combat triggers when ants are within 0.6 cells of each other
- Damage = `attacker.attack * variance - defender.defense * mitigation`
- Dead ants are removed; surviving enemies continue toward nest

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
- **Game engine** (lib/src/game/) - Flame integration, rendering, input
- **UI layer** (lib/src/ui/) - Flutter widgets, overlays
- **Persistence** (lib/src/state/) - Save/load functionality

The simulation can run headless for testing. The game layer is a thin rendering wrapper. The UI is stateless and driven by ValueNotifiers from the simulation.
