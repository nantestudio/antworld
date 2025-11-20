import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'ant.dart';
import 'simulation_config.dart';
import 'world_grid.dart';

class ColonySimulation {
  ColonySimulation(this.config)
      : antCount = ValueNotifier<int>(0),
        foodCollected = ValueNotifier<int>(0),
        pheromonesVisible = ValueNotifier<bool>(true),
        antSpeedMultiplier = ValueNotifier<double>(1.0) {
    world = WorldGrid(config);
  }

  SimulationConfig config;
  late WorldGrid world;
  final List<Ant> ants = [];
  final ValueNotifier<int> antCount;
  final ValueNotifier<int> foodCollected;
  final ValueNotifier<bool> pheromonesVisible;
  final ValueNotifier<double> antSpeedMultiplier;

  final math.Random _rng = math.Random();
  int _storedFood = 0;
  int _queuedAnts = 0;

  bool get showPheromones => pheromonesVisible.value;

  void initialize() {
    world.reset();
    world.carveNest();
    ants.clear();
    _storedFood = 0;
    _queuedAnts = 0;
    foodCollected.value = 0;

    for (var i = 0; i < config.startingAnts; i++) {
      _spawnAnt();
    }
    _updateAntCount();
  }

  void update(double dt) {
    final double clampedDt = dt.clamp(0.0, 0.05);
    final decayFactor = math.pow(config.decayPerSecond, clampedDt).toDouble();
    final double antSpeed = config.antSpeed * antSpeedMultiplier.value;
    world.decay(decayFactor, config.decayThreshold);

    for (final ant in ants) {
      final delivered = ant.update(clampedDt, config, world, _rng, antSpeed);
      if (delivered) {
        _storedFood += 1;
        foodCollected.value = _storedFood;
        if (_storedFood % config.foodPerNewAnt == 0) {
          _queuedAnts += 1;
        }
      }
    }

    _flushSpawnQueue();
  }

  void togglePheromones() {
    pheromonesVisible.value = !pheromonesVisible.value;
  }

  void setPheromoneVisibility(bool visible) {
    pheromonesVisible.value = visible;
  }

  void dig(Vector2 cellPosition) {
    world.digCircle(cellPosition, config.digBrushRadius);
  }

  void placeFood(Vector2 cellPosition) {
    world.placeFood(cellPosition, config.foodBrushRadius);
  }

  void addAnts(int count) {
    if (count <= 0) return;
    for (var i = 0; i < count; i++) {
      _spawnAnt();
    }
  }

  void removeAnts(int count) {
    if (count <= 0) return;
    final targetLength = math.max(1, ants.length - count);
    if (targetLength >= ants.length) return;
    ants.removeRange(targetLength, ants.length);
    _updateAntCount();
  }

  void scatterFood({int clusters = 6, int radius = 2}) {
    for (var i = 0; i < clusters; i++) {
      final gx = _rng.nextInt(world.cols);
      final gy = _rng.nextInt(world.rows);
      world.placeFood(Vector2(gx.toDouble(), gy.toDouble()), radius);
    }
  }

  void setAntSpeedMultiplier(double multiplier) {
    antSpeedMultiplier.value = multiplier.clamp(0.2, 5.0);
  }

  void resizeWorld({required int cols, required int rows}) {
    config = config.copyWith(cols: cols, rows: rows);
    world = WorldGrid(config);
    initialize();
  }

  void _spawnAnt() {
    ants.add(
      Ant(
        startPosition: world.nestPosition,
        initialAngle: _rng.nextDouble() * math.pi * 2,
      ),
    );
    _updateAntCount();
  }

  void _flushSpawnQueue() {
    if (_queuedAnts == 0) {
      return;
    }
    for (var i = 0; i < _queuedAnts; i++) {
      _spawnAnt();
    }
    _queuedAnts = 0;
  }

  void _updateAntCount() {
    antCount.value = ants.length;
  }
}
