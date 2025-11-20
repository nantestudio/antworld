# AntWorld 🐜

A real-time ant colony simulation built with Flutter and Flame, demonstrating emergent behavior through pheromone-based navigation. Watch as individual ants with simple rules create complex colony-wide patterns like foraging highways and efficient food collection.

## Table of Contents

- [Quick Start](#quick-start)
- [What is AntWorld?](#what-is-antworld)
- [How It Works](#how-it-works)
  - [Core Concepts](#core-concepts)
  - [Ant Behavior System](#ant-behavior-system)
  - [Pheromone Mechanics](#pheromone-mechanics)
  - [Energy System](#energy-system)
- [Architecture](#architecture)
- [User Controls](#user-controls)
- [Extending AntWorld](#extending-antworld)
- [Technical Details](#technical-details)

---

## Quick Start

### Prerequisites

- Flutter SDK 3.x or higher
- Dart 3.x or higher

### Running the App

```bash
# Install dependencies
flutter pub get

# Run on your preferred platform
flutter run

# For web
flutter run -d chrome

# For desktop
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
```

---

## What is AntWorld?

AntWorld simulates a realistic ant colony using **emergent behavior** - complex patterns that arise from simple individual rules. Each ant operates independently with basic logic:

- **Look** for pheromone trails with 3 sensors
- **Move** toward stronger signals
- **Drop** pheromones as they travel
- **Pick up** food when found
- **Return** home following a different pheromone

From these simple behaviors, the colony collectively:
- Discovers food sources through random exploration
- Creates optimal highways between food and nest
- Self-organizes without central coordination
- Adapts to terrain changes dynamically

---

## How It Works

### Core Concepts

#### 1. The World Grid

The world is a 2D grid where each cell can be:
- **Air** (walkable, transparent)
- **Dirt** (obstacle, can be dug through)
- **Food** (collectible resource)
- **Rock** (permanent obstacle)

The **nest** is located at the center of the world `(cols/2, rows/2)` and serves as the home base where ants spawn and deliver food.

```
Grid Structure:
┌─────────────────────────────┐
│ □ □ ▓ □ □ □ □ ▓ □ □ □ □ □ │  □ = Air
│ □ □ ▓ ▓ □ □ □ □ □ □ ● □ □ │  ▓ = Dirt
│ □ □ □ □ □ □ · □ □ □ □ □ □ │  ● = Food
│ □ □ □ · · · · · □ □ □ □ □ │  · = Air (with nest)
│ □ □ · · · ♔ · · · □ □ □ □ │  ♔ = Nest (center)
│ □ □ □ · · · · · □ □ □ □ □ │
│ □ □ □ □ □ □ · □ □ □ □ □ □ │
│ □ □ ▓ □ □ □ □ □ □ ● □ □ □ │
└─────────────────────────────┘
```

#### 2. Pheromones - The Chemical Language

Ants communicate using two types of pheromones:

- **Food Pheromone (Blue)** - "Food is this way!"
  - Deposited by ants carrying food (strength: 0.5)
  - Followed by ants in "foraging" state

- **Home Pheromone (Gray)** - "Nest is this way!"
  - Deposited by ants without food (strength: 0.2)
  - Followed by ants in "returning home" state
  - Nest center always has strength 1.0

Pheromones:
- **Decay** over time (multiply by 0.985 per frame)
- **Accumulate** when multiple ants travel the same path
- **Guide** other ants using their sensors

---

### Ant Behavior System

Each ant has:
- **Position** (x, y coordinates)
- **Angle** (direction in radians)
- **Energy** (100 max, depletes as they move)
- **State** (forage, returnHome, or rest)
- **Carrying Food** (boolean flag)

#### Ant State Machine

```
        ┌──────────────┐
        │   FORAGING   │◄─────────┐
        └───────┬──────┘           │
                │                  │
         Found Food              Delivered
                │                Food
                ▼                  │
        ┌──────────────┐           │
        │ RETURN HOME  │───────────┘
        └───────┬──────┘
                │
         Energy = 0
                │
                ▼
        ┌──────────────┐
        │     REST     │
        └───────┬──────┘
                │
         Energy Full
                │
                └─────────► Resume Previous State
```

#### The Movement Algorithm (every frame)

Here's what happens each frame for each ant:

**Step 1: Energy Check**
```
IF energy <= 0:
    Enter REST state
    Stop moving
    Recover energy at 0.5/second
    RETURN
ELSE:
    Lose 1 energy per second
```

**Step 2: Sense Environment (3 Sensors)**

Each ant has 3 "antennae" that detect pheromones:

```
        LEFT         FRONT        RIGHT
         ▲             ▲             ▲
          ╲            |            ╱
           ╲           |           ╱
            ╲          |          ╱
           -0.6rad   angle    +0.6rad
                 ╲     |     ╱
                  ╲    |    ╱
                   ╲   |   ╱
                    ╲  |  ╱
                     ╲ | ╱
                      ╲|╱
                       🐜 ← ant position
```

- Each sensor reaches **6 cells** away
- Sensors detect:
  - **Food pheromone** if ant is foraging
  - **Home pheromone** if ant is carrying food
  - **Actual food** gets +10 bonus signal

**Step 3: Steering Decision**
```
IF front_sensor > left AND front_sensor > right:
    → Go straight (tiny random wiggle)
ELSE IF left_sensor > right_sensor:
    → Turn LEFT (0.1-0.3 radians)
ELSE IF right_sensor > left_sensor:
    → Turn RIGHT (0.1-0.3 radians)
ELSE:
    → Random wander (small random turn)
```

**Step 4: Direct Food Sensing** (only when foraging)
```
IF no strong pheromone detected AND foraging:
    Check for food within 30 cells
    IF food found:
        Gradually turn toward food
```

This dual-sensing system means:
- Established trails are followed via pheromones (efficient)
- New food sources are discovered via direct sensing (exploration)

**Step 5: Move Forward**
```
velocity_x = cos(angle) * speed * delta_time
velocity_y = sin(angle) * speed * delta_time
new_position = current_position + velocity

IF hit boundary:
    Turn around 180°
    Don't move
ELSE IF hit dirt:
    Dig dirt (costs energy)
    Turn away
    Don't move
ELSE:
    Move to new_position
```

**Step 6: Drop Pheromone Trail**
```
IF carrying food:
    Drop FOOD pheromone at current position (strength 0.5)
ELSE:
    Drop HOME pheromone at current position (strength 0.2)
```

**Step 7: Food Interaction**
```
IF on food cell AND not carrying food:
    Pick up food
    Turn around ~180°
    Switch to RETURN_HOME state
    Remove food from world
```

**Step 8: Nest Interaction**
```
IF distance_to_nest < 3.5 AND carrying food:
    Drop food (colony stores it)
    Turn around 180°
    Switch to FORAGING state
    Increment food counter
```

---

### Pheromone Mechanics

#### Why Trails Form

When one ant finds food:

1. **Discovery Phase**
   ```
   Ant wanders randomly → Gets within 30 cells of food →
   Senses food directly → Walks to food → Picks it up
   ```

2. **Trail Creation**
   ```
   While returning home:
   🐜→→→→→→→→→→→♔
   💙💙💙💙💙💙💙   (drops food pheromone)
   ```

3. **Trail Following**
   ```
   Other foraging ants detect the trail:
   🐜 (senses blue pheromone with left sensor)
    ╲
     ╲ (turns left toward stronger signal)
      ╲
       ▼
      💙💙💙→→→→ (follows trail to food)
   ```

4. **Trail Reinforcement**
   ```
   More ants use trail → More pheromone deposited →
   Trail gets stronger → Attracts even more ants →
   Creates "ant highway"
   ```

5. **Trail Decay**
   ```
   Unused trails fade over time (decay rate: 0.985 per frame)
   When food depleted → Ants stop reinforcing →
   Trail fades → Ants explore elsewhere
   ```

#### Pheromone Data Structure

```dart
// Two separate grids overlay the world
Float32List foodPheromones[cols * rows]  // Blue trails
Float32List homePheromones[cols * rows]  // Gray trails

// Each frame:
for each cell:
    foodPheromones[i] *= 0.985  // Decay
    homePheromones[i] *= 0.985

// Special case: nest always emits max home pheromone
homePheromones[nestIndex] = 1.0
```

---

### Energy System

Ants have a **stamina system** to simulate realistic limits:

```
Energy Capacity: 100
Decay Rate: 1 per second
Recovery Rate: 0.5 per second (while resting)
Digging Cost: 0.5 per dig attempt
```

**Energy Flow Diagram:**

```
                    ┌─────────────┐
                    │   Moving    │ -1 energy/sec
                    └──────┬──────┘
                           │
                           ▼
                    Energy Reaches 0
                           │
                           ▼
                    ┌─────────────┐
                    │   Resting   │ +0.5 energy/sec
                    └──────┬──────┘
                           │
                           ▼
                    Energy Reaches 100
                           │
                           ▼
                    Resume Previous State
```

**Digging Mechanics:**
- Dirt has 100 health
- Each dig attempt costs 0.5 energy
- Deals 0.5 damage (1:1 ratio)
- Ant turns away after hitting dirt
- When dirt health reaches 0, cell becomes air

---

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────┐
│                   main.dart                      │
│              (Flutter App Entry)                 │
└───────┬────────────────────────────┬────────────┘
        │                            │
        ▼                            ▼
┌──────────────────┐         ┌─────────────────┐
│  AntWorldGame    │         │   AntHud        │
│  (Flame Game)    │         │   (Flutter UI)  │
│  - Rendering     │         │   - Controls    │
│  - Input         │         │   - Settings    │
└────────┬─────────┘         │   - Stats       │
         │                   └─────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│      ColonySimulation               │
│  - Update loop                      │
│  - Manages ants list                │
│  - Coordinates simulation           │
└────────┬────────────────────────────┘
         │
         ├──────────┬──────────────┐
         ▼          ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│   Ant    │  │WorldGrid │  │SimulationConfig
│  (List)  │  │  (Grid)  │  │   (Settings)  │
└──────────┘  └──────────┘  └──────────────┘
```

### Data Flow

#### Update Loop (60 FPS)

```
EVERY FRAME:

1. AntWorldGame.update(dt)
   │
   ├──> 2. ColonySimulation.update(dt)
   │     │
   │     ├──> 3. WorldGrid.decay(...)
   │     │     └──> Reduce all pheromone strengths
   │     │
   │     └──> 4. For each Ant:
   │           ├──> ant.update(dt, config, world, rng, speed)
   │           │    │
   │           │    ├──> Check energy
   │           │    ├──> Sense pheromones (3 sensors)
   │           │    ├──> Decide steering
   │           │    ├──> Move forward
   │           │    ├──> Drop pheromone
   │           │    ├──> Check food pickup
   │           │    └──> Check food delivery
   │           │
   │           └──> IF food delivered:
   │                 └──> Increment food counter
   │                 └──> Maybe spawn new ant
   │
   └──> 5. AntWorldGame.render(canvas)
         └──> Draw terrain, pheromones, ants, nest
```

### File Structure

```
lib/
├── main.dart                          # App entry point
├── src/
    ├── game/
    │   └── ant_world_game.dart       # Flame game engine (rendering, input)
    ├── simulation/
    │   ├── ant.dart                   # Individual ant logic & state machine
    │   ├── colony_simulation.dart     # Colony manager & update orchestrator
    │   ├── simulation_config.dart     # All tunable parameters
    │   └── world_grid.dart            # Grid data structure & pheromones
    ├── ui/
    │   └── ant_hud.dart               # UI controls & settings panel
    └── state/
        └── simulation_storage.dart     # Save/load world state
```

---

## User Controls

### Mouse/Touch Controls

| Action | Effect |
|--------|--------|
| **Left Click** | Use active brush (dig/food/rock) |
| **Right Click** | Place food (overrides current brush) |
| **Shift + Click** | Place food (overrides current brush) |
| **Drag** | Paint continuously with active brush |

### Keyboard Controls

| Key | Effect |
|-----|--------|
| **P** | Toggle pheromone visibility |

### UI Controls

**Top Bar:**
- **Ant count** - Current population
- **Food collected** - Total food delivered to nest
- **Settings button** - Open/close settings panel

**Bottom Control Panel:**
- **Brush Mode** - Select dig/food/rock tool
- **Pheromones** - Toggle visibility on/off

**Settings Panel:**
- **Ant Population** - Add/remove ants (±1, ±10)
- **Ant Speed** - Adjust speed multiplier (0.2x - 3.0x)
- **Scatter Food** - Drop random food clusters
- **Save World** - Persist current state to local storage
- **Grid Size** - Resize world (40-160 cols, 30-140 rows)

---

## Extending AntWorld

### Adding New Ant Behaviors

**1. Add a new state to the state machine:**

```dart
// In lib/src/simulation/ant.dart
enum AntState {
  forage,
  returnHome,
  rest,
  explore,      // ← New state
}
```

**2. Implement state-specific logic in `ant.update(...)`:**

```dart
// In ant.dart, modify the update method
if (state == AntState.explore) {
  // Custom exploration behavior
  // Example: move in wider circles, ignore pheromones
  angle += (rng.nextDouble() - 0.5) * 0.5; // More random
  // Skip pheromone sensing
}
```

**3. Add transition logic:**

```dart
// When to enter explore state?
if (state == AntState.forage && timeSinceLastFood > 30) {
  state = AntState.explore;
}
```

---

### Adding New Pheromone Types

**1. Add pheromone data to WorldGrid:**

```dart
// In lib/src/simulation/world_grid.dart
class WorldGrid {
  final Float32List foodPheromones;
  final Float32List homePheromones;
  final Float32List dangerPheromones;  // ← New pheromone

  WorldGrid(this.config)
    : foodPheromones = Float32List(config.cols * config.rows),
      homePheromones = Float32List(config.cols * config.rows),
      dangerPheromones = Float32List(config.cols * config.rows);  // ← Initialize
}
```

**2. Add deposit/sense methods:**

```dart
void depositDangerPheromone(int x, int y, double amount) {
  final idx = index(x, y);
  dangerPheromones[idx] = math.min(1.0, dangerPheromones[idx] + amount);
}

double dangerPheromoneAt(int x, int y) => dangerPheromones[index(x, y)];
```

**3. Include in decay cycle:**

```dart
// In WorldGrid.decay(...)
void decay(double factor, double threshold) {
  for (var i = 0; i < dangerPheromones.length; i++) {
    var d = dangerPheromones[i];
    if (d > threshold) {
      d *= factor;
      dangerPheromones[i] = d > threshold ? d : 0;
    }
  }
}
```

**4. Make ants react to it:**

```dart
// In ant.dart _sense method
double _sense(double direction, SimulationConfig config, WorldGrid world) {
  // ... existing code ...

  final dangerLevel = world.dangerPheromoneAt(gx, gy);
  if (dangerLevel > 0.5) {
    return -1000;  // Strongly avoid this cell
  }

  // ... continue normal sensing ...
}
```

---

### Adding New Cell Types

**1. Add to the CellType enum:**

```dart
// In lib/src/simulation/world_grid.dart
enum CellType {
  air,
  dirt,
  food,
  rock,
  water,  // ← New cell type
}
```

**2. Add rendering logic:**

```dart
// In lib/src/game/ant_world_game.dart
final Paint _waterPaint = Paint()..color = const Color(0xFF2196F3);

void _drawTerrain(Canvas canvas, WorldGrid world, double cellSize) {
  // ... existing code ...

  if (cellValue == CellType.water.index) {
    canvas.drawRect(rect, _waterPaint);
  }
}
```

**3. Add interaction logic:**

```dart
// In ant.dart update method
if (block == CellType.water) {
  // Ants move slower in water
  final waterSpeedMultiplier = 0.5;
  final distance = antSpeed * dt * waterSpeedMultiplier;
  // ... rest of movement ...
}
```

**4. Add placement method:**

```dart
// In world_grid.dart
void placeWater(Vector2 cellPos, int radius) {
  final cx = cellPos.x.floor();
  final cy = cellPos.y.floor();
  for (var dx = -radius; dx <= radius; dx++) {
    for (var dy = -radius; dy <= radius; dy++) {
      final nx = cx + dx;
      final ny = cy + dy;
      if (!isInsideIndex(nx, ny)) continue;
      if (dx * dx + dy * dy <= radius * radius) {
        setCell(nx, ny, CellType.water);
      }
    }
  }
}
```

**5. Add UI brush option:**

```dart
// In ant_world_game.dart
enum BrushMode { dig, food, rock, water }  // ← Add water

// In ant_hud.dart, add to SegmentedButton
ButtonSegment(
  value: BrushMode.water,
  label: Text('Water'),
  icon: Icon(Icons.water),
),
```

---

### Tuning Simulation Parameters

All behavior is controlled by `SimulationConfig`. Modify these in `lib/src/simulation/simulation_config.dart`:

```dart
const SimulationConfig({
  // World size
  this.cols = 100,              // Grid width
  this.rows = 75,               // Grid height
  this.cellSize = 8,            // Pixels per cell

  // Population
  this.startingAnts = 20,       // Initial ant count
  this.foodPerNewAnt = 3,       // Food needed to spawn ant

  // Movement
  this.antSpeed = 48,           // Cells per second
  this.sensorDistance = 6,      // How far sensors reach
  this.sensorAngle = 0.6,       // Angle between sensors (radians)

  // Pheromones
  this.foodDepositStrength = 0.5,   // Food pheromone intensity
  this.homeDepositStrength = 0.2,   // Home pheromone intensity
  this.decayPerFrame = 0.985,       // Pheromone decay multiplier
  this.decayThreshold = 0.01,       // Minimum before removed

  // Interaction
  this.foodPickupRotation = math.pi,    // Turn amount on pickup
  this.nestRadius = 3,                  // Nest size
  this.foodSenseRange = 30,             // Direct food detection range

  // Energy
  this.energyCapacity = 100,            // Max energy
  this.energyDecayPerSecond = 1,        // Energy loss rate
  this.energyRecoveryPerSecond = 0.5,   // Energy recovery rate
  this.digEnergyCost = 0.5,             // Energy per dig

  // Terrain
  this.dirtMaxHealth = 100,             // Dirt durability
  this.digDamagePerEnergy = 1,          // Damage per energy spent
  this.digBrushRadius = 1,              // Brush size for digging
  this.foodBrushRadius = 2,             // Brush size for food placement
});
```

**Example: Make ants move faster and sense further**

```dart
const SimulationConfig(
  antSpeed: 96,           // 2x speed (was 48)
  sensorDistance: 12,     // 2x range (was 6)
  // ... other defaults ...
);
```

**Example: Make pheromones last longer**

```dart
const SimulationConfig(
  decayPerFrame: 0.995,   // Slower decay (was 0.985)
  // Trails will last ~30% longer
);
```

---

### Adding Analytics/Metrics

**1. Track custom metrics in ColonySimulation:**

```dart
class ColonySimulation {
  final ValueNotifier<int> antCount;
  final ValueNotifier<int> foodCollected;
  final ValueNotifier<int> totalDistanceTraveled = ValueNotifier<int>(0);  // ← New
  final ValueNotifier<int> totalDigsPerformed = ValueNotifier<int>(0);     // ← New

  void update(double dt) {
    // ... existing code ...

    for (final ant in ants) {
      final oldPos = ant.position.clone();
      ant.update(...);
      final newPos = ant.position;

      // Track distance
      final distance = oldPos.distanceTo(newPos);
      totalDistanceTraveled.value += distance.round();
    }
  }
}
```

**2. Display in UI:**

```dart
// In ant_hud.dart
_StatCard(
  label: 'Distance',
  listenable: widget.simulation.totalDistanceTraveled
),
```

**3. Export data:**

```dart
Map<String, dynamic> getAnalytics() {
  return {
    'foodCollected': foodCollected.value,
    'antCount': antCount.value,
    'averageDistancePerAnt': totalDistanceTraveled.value / antCount.value,
    'efficiency': foodCollected.value / (totalDistanceTraveled.value / 1000),
  };
}
```

---

### Implementing Multi-Colony Simulation

**1. Make nests identifiable:**

```dart
class Nest {
  final Vector2 position;
  final Color color;
  final int id;
  int storedFood = 0;

  Nest(this.id, this.position, this.color);
}
```

**2. Assign ants to colonies:**

```dart
class Ant {
  final int colonyId;
  // ... existing fields ...

  Ant({
    required this.colonyId,  // ← Which nest this ant belongs to
    // ... existing params ...
  });
}
```

**3. Use colony-specific pheromones:**

```dart
class WorldGrid {
  // Instead of:
  // final Float32List homePheromones;

  // Use:
  final Map<int, Float32List> colonyHomePheromones;  // One per colony

  double homePheromoneAt(int x, int y, int colonyId) {
    return colonyHomePheromones[colonyId]![index(x, y)];
  }
}
```

**4. Update ant sensing to use colony ID:**

```dart
double _sense(double direction, SimulationConfig config, WorldGrid world) {
  // ... existing code ...

  if (behavior == AntState.returnHome) {
    return world.homePheromoneAt(gx, gy, this.colonyId);  // ← Colony-specific
  }
}
```

---

## Technical Details

### Performance Optimizations

1. **Terrain Caching** - Static terrain is rendered once to a `Picture` object and reused every frame
2. **Pheromone Decay** - Only processes cells above threshold (0.01)
3. **Food Indexing** - Maintains a `Set<int>` of food cell indices for O(1) lookup instead of scanning entire grid
4. **Delta Time Clamping** - Caps `dt` at 0.05s to prevent physics instability during lag spikes

### Save/Load System

World state is persisted using Flutter's `shared_preferences`:

**Saved Data:**
- All simulation config parameters
- Complete grid state (cells, dirt health, pheromones)
- All ant positions, angles, states, energy
- Food collected count
- UI settings (speed multiplier, pheromone visibility)

**Data Encoding:**
- Typed arrays encoded as base64 strings
- JSON structure for easy debugging
- Automatic restore on app launch

### Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Web | ✅ Full support | Best performance on Chrome/Edge |
| macOS | ✅ Full support | Native desktop app |
| Windows | ✅ Full support | Native desktop app |
| Linux | ✅ Full support | Native desktop app |
| iOS | ⚠️ Untested | Should work, needs testing |
| Android | ⚠️ Untested | Should work, needs testing |

---

## Development Roadmap Ideas

Here are some ideas for extending AntWorld:

### Beginner-Friendly Extensions
- [ ] Add day/night cycle (ants rest at night)
- [ ] Different food types with varying nutrition values
- [ ] Ant names/labels for individual tracking
- [ ] More color schemes and themes
- [ ] Sound effects for ant actions
- [ ] Achievement system (collect 100 food, etc.)

### Intermediate Extensions
- [ ] Predators that hunt ants
- [ ] Weather system (rain slows ants)
- [ ] Obstacles that require teamwork to overcome
- [ ] Ant specialization (workers, soldiers, scouts)
- [ ] Multiple food sources with priorities
- [ ] Replay system to watch simulations

### Advanced Extensions
- [ ] Multi-colony competition/cooperation
- [ ] Genetic algorithms for ant behavior evolution
- [ ] 3D visualization mode
- [ ] Machine learning for optimal foraging
- [ ] Network multiplayer (shared worlds)
- [ ] Custom scripting language for behaviors

---

## Credits

Built with:
- [Flutter](https://flutter.dev) - UI framework
- [Flame](https://flame-engine.org) - Game engine
- Inspired by biological ant colony behavior and Sebastian Lague's ant simulation

## License

MIT License - feel free to use this for learning, teaching, or building upon!

---

**Happy ant watching! 🐜✨**
