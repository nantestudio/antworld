# AntWorld

A real-time ant colony simulation built with Flutter and Flame. Watch emergent behavior unfold as ants with simple rules create complex colony-wide patterns like foraging highways and efficient food collection.

## Quick Start

```bash
flutter pub get
flutter run
```

Supports: iOS, Android, macOS, Windows, Linux, Web

## What It Does

Each ant follows basic rules:
- Sense pheromone trails with 3 sensors
- Move toward stronger signals
- Drop pheromones while traveling
- Pick up food when found
- Return home following pheromone trails

From these simple behaviors, colonies self-organize to:
- Discover food through exploration
- Create optimal highways between food and nest
- Adapt to terrain changes dynamically
- Defend against enemy colonies
- Raise new generations through queens

## Features

### Sandbox Mode
Endless colony building with full creative control. Dig tunnels, place food, and watch your colony grow.

### Multiple Colonies (1-4)
Each colony has its own pheromone trails, nest, and tribe name (randomly generated names like "Thornveil", "Ironmaw", "Shadowmire"). Colonies compete for resources and territory.

### Ant Castes
- **Worker** - Foraging and digging
- **Soldier** - Defense and patrol
- **Nurse** - Egg and larva care
- **Queen** - Egg laying
- **Princess** - Succession (promotes to queen if queen dies)
- **Builder** - Fast digging, weak combat
- **Egg/Larva** - Development stages

### Mother Nature Events
Random environmental events keep the world dynamic:
- **Food Blooms** - New food sources appear
- **Tunnel Collapse** - Old tunnels fill with dirt
- **Rock Falls** - Debris drops into tunnels
- **Predator Raids** - Wild ant attacks from map edges
- **Earthquakes** - Terrain disruption
- **Hidden Chambers** - Discover treasure rooms
- **Seasons** - Spring, Summer, Fall, Winter affect event frequency

### Pheromone System
- Food pheromones guide ants to food sources
- Home pheromones guide ants back to nest
- Colony-specific trails (ants only sense their own colony's pheromones)
- Trails decay over time, stronger trails attract more ants

### Terrain
- **Air** - Walkable space
- **Dirt** - Variable hardness (soft sand to bedrock)
- **Food** - Collectible resource
- **Rock** - Permanent obstacle

## Controls

- **Brush tools** - Dig, place food, place rock
- **Speed control** - Adjust simulation speed
- **Pheromone toggle** - Show/hide pheromone trails
- **Pinch to zoom** - Adjust view

## Architecture

```
lib/
├── main.dart                    # App entry
├── src/
    ├── game/                    # Flame game engine, rendering
    ├── simulation/              # Core logic (ants, world, colonies)
    ├── services/                # Mother Nature, analytics
    ├── ui/                      # Flutter widgets, HUD
    ├── visuals/                 # Ant sprites, rendering
    ├── state/                   # Save/load
    └── core/                    # Game state, events
```

## Tech Stack

- [Flutter](https://flutter.dev) - UI framework
- [Flame](https://flame-engine.org) - Game engine
- Firebase Analytics - Usage tracking

## License

MIT

