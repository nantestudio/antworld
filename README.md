# AntWorld

A real-time ant colony simulation built with Flutter and Flame—an experiment in building a game entirely with [Claude Code](https://claude.ai/code).

## The Vision

I wanted to create something like Cities Skylines meets Mini Motorways, but with ants. The goal was to test whether Claude Code could handle full game development through an iterative build-and-verify loop.

## What I Learned

**The hard parts:**
- Performance debugging is tough without deep game engine knowledge
- Couldn't crack the "production-ready fun game loop" problem

**The good parts:**
- The simulation + ant colony theme resonated with people
- Watching ants organically form pheromone highways and expand their colony is genuinely satisfying
- Emergent behavior from simple rules actually works

This started as a study project. I'd like to revisit it someday.

*Sharing because a redditor asked to see the code.*

## How It Works

Each ant follows simple rules: sense pheromones with 3 sensors, move toward stronger signals, drop pheromones, collect food, return home. From this, colonies self-organize into foraging highways and adapt to terrain changes.

## Features

- **1-4 competing colonies** with unique pheromone trails
- **Castes**: Worker, Soldier, Nurse, Queen, Princess, Builder, Egg, Larva
- **Environmental events**: Food blooms, tunnel collapses, predator raids, seasons
- **Sandbox tools**: Dig tunnels, place food, shape the world

## Quick Start

```bash
flutter pub get
flutter run
```

Runs on iOS, Android, macOS, Windows, Linux, and Web.

## Why Flutter + Flame?

1. **Familiar territory** — I already knew Flutter from app development
2. **Pure code** — Unlike Godot or Unity, no visual editors required. Claude Code could handle 100% of the work.

## License

MIT
