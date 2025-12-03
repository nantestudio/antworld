/// Evolution Tracker Service - Tracks session metrics for AI evolution
///
/// Collects performance data during gameplay and triggers evolution
/// at the end of each session to improve simulation parameters.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'hive_mind_service.dart';

/// Session metrics collected during gameplay
class SessionMetrics {
  int survivalDays;
  int peakFood;
  int peakAnts;
  int battlesWon;
  int battlesLost;
  int coloniesConquered;
  int coloniesLost;

  SessionMetrics({
    this.survivalDays = 0,
    this.peakFood = 0,
    this.peakAnts = 0,
    this.battlesWon = 0,
    this.battlesLost = 0,
    this.coloniesConquered = 0,
    this.coloniesLost = 0,
  });

  Map<String, dynamic> toJson() => {
        'survivalDays': survivalDays,
        'peakFood': peakFood,
        'peakAnts': peakAnts,
        'battlesWon': battlesWon,
        'battlesLost': battlesLost,
        'coloniesConquered': coloniesConquered,
        'coloniesLost': coloniesLost,
      };

  factory SessionMetrics.fromJson(Map<String, dynamic> json) {
    return SessionMetrics(
      survivalDays: json['survivalDays'] as int? ?? 0,
      peakFood: json['peakFood'] as int? ?? 0,
      peakAnts: json['peakAnts'] as int? ?? 0,
      battlesWon: json['battlesWon'] as int? ?? 0,
      battlesLost: json['battlesLost'] as int? ?? 0,
      coloniesConquered: json['coloniesConquered'] as int? ?? 0,
      coloniesLost: json['coloniesLost'] as int? ?? 0,
    );
  }
}

/// Evolved parameters that can be applied to simulation
class EvolvedParams {
  final Map<String, double> params;
  final int generation;
  final double fitnessScore;
  final String? reasoning;

  const EvolvedParams({
    required this.params,
    required this.generation,
    this.fitnessScore = 0,
    this.reasoning,
  });

  Map<String, dynamic> toJson() => {
        'params': params,
        'generation': generation,
        'fitnessScore': fitnessScore,
        if (reasoning != null) 'reasoning': reasoning,
      };

  factory EvolvedParams.fromJson(Map<String, dynamic> json) {
    return EvolvedParams(
      params: (json['params'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {},
      generation: json['generation'] as int? ?? 1,
      fitnessScore: (json['fitnessScore'] as num?)?.toDouble() ?? 0,
      reasoning: json['reasoning'] as String?,
    );
  }

  /// Default parameters before any evolution
  static const defaultParams = EvolvedParams(
    params: {
      'explorerRatio': 0.05,
      'workerRatio': 0.55,
      'soldierRatio': 0.15,
      'nurseRatio': 0.15,
      'builderRatio': 0.10,
      'pheromoneDecay': 0.985,
      'foodPheromoneStrength': 0.5,
      'homePheromoneStrength': 0.2,
    },
    generation: 0,
    fitnessScore: 0,
  );
}

/// Singleton service for tracking evolution metrics
class EvolutionTracker {
  EvolutionTracker._();
  static final instance = EvolutionTracker._();

  // Storage keys
  static const _evolvedParamsKey = 'evolution_params';
  static const _generationKey = 'evolution_generation';

  // State
  SessionMetrics _currentMetrics = SessionMetrics();
  bool _isTracking = false;
  EvolvedParams? _currentEvolvedParams;
  int _currentGeneration = 1;

  // Supabase client
  SupabaseClient? _supabase;

  /// Initialize with Supabase (call after HiveMindService.initialize)
  Future<void> initialize() async {
    try {
      _supabase = Supabase.instance.client;

      // Load evolved params from storage
      final prefs = await SharedPreferences.getInstance();
      final paramsJson = prefs.getString(_evolvedParamsKey);
      _currentGeneration = prefs.getInt(_generationKey) ?? 1;

      if (paramsJson != null) {
        try {
          final decoded = _parseJson(paramsJson);
          _currentEvolvedParams = EvolvedParams.fromJson(decoded);
          debugPrint(
              'EvolutionTracker: Loaded generation ${_currentEvolvedParams!.generation} params');
        } catch (e) {
          debugPrint('EvolutionTracker: Failed to parse stored params: $e');
          _currentEvolvedParams = null;
        }
      }

      debugPrint('EvolutionTracker: Initialized (generation $_currentGeneration)');
    } catch (e) {
      debugPrint('EvolutionTracker: Initialize failed: $e');
    }
  }

  /// Get current evolved parameters (or defaults if none)
  EvolvedParams get evolvedParams =>
      _currentEvolvedParams ?? EvolvedParams.defaultParams;

  /// Get current generation number
  int get generation => _currentGeneration;

  /// Start tracking a new session
  void startSession() {
    _currentMetrics = SessionMetrics();
    _isTracking = true;
    debugPrint('EvolutionTracker: Session started');
  }

  /// Update survival days
  void updateSurvivalDays(int days) {
    if (!_isTracking) return;
    _currentMetrics.survivalDays = math.max(_currentMetrics.survivalDays, days);
  }

  /// Update peak food
  void updatePeakFood(int food) {
    if (!_isTracking) return;
    _currentMetrics.peakFood = math.max(_currentMetrics.peakFood, food);
  }

  /// Update peak ants
  void updatePeakAnts(int ants) {
    if (!_isTracking) return;
    _currentMetrics.peakAnts = math.max(_currentMetrics.peakAnts, ants);
  }

  /// Record a battle won
  void recordBattleWon() {
    if (!_isTracking) return;
    _currentMetrics.battlesWon++;
  }

  /// Record a battle lost
  void recordBattleLost() {
    if (!_isTracking) return;
    _currentMetrics.battlesLost++;
  }

  /// Record a colony conquered
  void recordColonyConquered() {
    if (!_isTracking) return;
    _currentMetrics.coloniesConquered++;
  }

  /// Record a colony lost
  void recordColonyLost() {
    if (!_isTracking) return;
    _currentMetrics.coloniesLost++;
  }

  /// End session and trigger evolution
  Future<void> endSession() async {
    if (!_isTracking) return;
    _isTracking = false;

    debugPrint('EvolutionTracker: Session ended');
    debugPrint('  Survival days: ${_currentMetrics.survivalDays}');
    debugPrint('  Peak food: ${_currentMetrics.peakFood}');
    debugPrint('  Peak ants: ${_currentMetrics.peakAnts}');
    debugPrint('  Battles: ${_currentMetrics.battlesWon}W/${_currentMetrics.battlesLost}L');

    // Only evolve if session was meaningful (survived at least 1 day)
    if (_currentMetrics.survivalDays < 1) {
      debugPrint('EvolutionTracker: Session too short, skipping evolution');
      return;
    }

    // Trigger evolution
    await _evolveParams();
  }

  /// Request evolution from AI
  Future<void> _evolveParams() async {
    if (_supabase == null) {
      debugPrint('EvolutionTracker: Supabase not initialized');
      return;
    }

    if (!HiveMindService.instance.isReady) {
      debugPrint('EvolutionTracker: HiveMind not ready, skipping evolution');
      return;
    }

    try {
      final generationId = 'gen-$_currentGeneration';
      final currentParams = evolvedParams.params;

      debugPrint('EvolutionTracker: Requesting evolution for $generationId');

      final response = await _supabase!.functions.invoke(
        'antworld-hive-mind-evolve',
        body: {
          'generationId': generationId,
          'currentParams': currentParams,
          'metrics': _currentMetrics.toJson(),
        },
      );

      if (response.status != 200) {
        debugPrint('EvolutionTracker: Evolution request failed: ${response.status}');
        return;
      }

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        debugPrint('EvolutionTracker: No data in evolution response');
        return;
      }

      // Parse evolved params
      final evolvedParamsMap = (data['evolvedParams'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {};

      if (evolvedParamsMap.isEmpty) {
        debugPrint('EvolutionTracker: No evolved params returned');
        return;
      }

      // Merge evolved params with current (only override what changed)
      final mergedParams = Map<String, double>.from(currentParams);
      mergedParams.addAll(evolvedParamsMap);

      final fitnessScore = (data['fitnessScore'] as num?)?.toDouble() ?? 0;
      final reasoning = data['reasoning'] as String?;

      // Increment generation
      _currentGeneration++;

      // Create new evolved params
      _currentEvolvedParams = EvolvedParams(
        params: mergedParams,
        generation: _currentGeneration,
        fitnessScore: fitnessScore,
        reasoning: reasoning,
      );

      // Save to storage
      await _saveEvolvedParams();

      debugPrint('EvolutionTracker: Evolution complete');
      debugPrint('  Generation: $_currentGeneration');
      debugPrint('  Fitness: $fitnessScore');
      debugPrint('  Reasoning: $reasoning');
      debugPrint('  Changed params: ${evolvedParamsMap.keys.join(', ')}');
    } catch (e) {
      debugPrint('EvolutionTracker: Evolution failed: $e');
    }
  }

  /// Save evolved params to local storage
  Future<void> _saveEvolvedParams() async {
    if (_currentEvolvedParams == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _evolvedParamsKey, _encodeJson(_currentEvolvedParams!.toJson()));
      await prefs.setInt(_generationKey, _currentGeneration);
      debugPrint('EvolutionTracker: Params saved to storage');
    } catch (e) {
      debugPrint('EvolutionTracker: Failed to save params: $e');
    }
  }

  /// Reset evolution (for testing or starting fresh)
  Future<void> resetEvolution() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_evolvedParamsKey);
      await prefs.remove(_generationKey);
      _currentEvolvedParams = null;
      _currentGeneration = 1;
      debugPrint('EvolutionTracker: Evolution reset');
    } catch (e) {
      debugPrint('EvolutionTracker: Failed to reset: $e');
    }
  }

  // JSON helpers
  Map<String, dynamic> _parseJson(String json) {
    // ignore: avoid_dynamic_calls
    return (const JsonDecoder().convert(json) as Map<String, dynamic>);
  }

  String _encodeJson(Map<String, dynamic> data) {
    return const JsonEncoder().convert(data);
  }
}
