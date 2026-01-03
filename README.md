# AntWorld

A real-time ant colony simulation built with Flutter and Flame. This was an experiment to see how far I could build a game using only [Claude Code](https://claude.ai/code) as the developer.

## The Experiment

The dream was ambitious: an ant-based civilization game meets Cities Skylines meets Mini Motorways. I wanted to test an iteration loop where Claude Code would implement features, then somehow verify if the result matched what we wanted to build.

### What I Learned

**Limitations for production games with Claude Code:**
- Can't debug performance issues well - without game engine knowledge, it's hard to make things super performant
- Got stuck trying to make it into a production-ready game with a fun game loop

**What worked:**
- People liked the concept - the simulation + ant colony theme resonated
- I personally enjoyed watching ants grow their pheromone paths and enlarge their colony
- The emergent behavior is genuinely satisfying to watch

This was a study project. I'd like to come back to it someday.

Sharing the code because a redditor asked to see it.

## What It Does

Each ant follows simple rules:
- Sense pheromone trails with 3 sensors
- Move toward stronger signals
- Drop pheromones while traveling
- Pick up food and return home

From these behaviors, colonies self-organize into foraging highways, adapt to terrain changes, and compete for resources.

## Features

- **Multiple colonies** (1-4) with unique pheromone trails and tribe names
- **Ant castes**: Worker, Soldier, Nurse, Queen, Princess, Builder, Egg, Larva
- **Mother Nature events**: Food blooms, tunnel collapses, predator raids, seasons
- **Sandbox mode**: Dig tunnels, place food, watch your colony grow

## Quick Start

```bash
flutter pub get
flutter run
```

Supports iOS, Android, macOS, Windows, Linux, and Web.

## Why Flutter + Flame?

I chose this stack because:
1. **I knew Flutter** - Comfortable with it from app development
2. **100% code-based** - Unlike Godot or Unity which require visual editors for scenes/UI, Flutter + Flame is purely code. Claude Code could handle everything without me touching any GUI tools.

## Tech

- [Flutter](https://flutter.dev) + [Flame](https://flame-engine.org)
- Firebase Analytics
- Pure Dart simulation (can run headless)

## License

MIT
