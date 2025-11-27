import 'package:flutter/foundation.dart';

import '../simulation/colony_simulation.dart';
import '../state/unified_storage.dart';
import 'event_bus.dart';
import 'game_event.dart';
import 'game_mode.dart';
import 'mode_config.dart';
import 'player_progress.dart';

class GameStateManager extends ChangeNotifier {
  GameStateManager({UnifiedStorage? storage, GameEventBus? eventBus})
    : _storage = storage ?? UnifiedStorage(),
      _eventBus = eventBus ?? GameEventBus();

  final UnifiedStorage _storage;
  final GameEventBus _eventBus;

  GameMode? _currentMode;
  ModeConfig? _currentConfig;
  ColonySimulation? _simulation;
  PlayerProgress _playerProgress = PlayerProgress.initial();
  bool _progressLoaded = false;
  bool _isLoading = false;

  GameEventBus get eventBus => _eventBus;
  UnifiedStorage get storage => _storage;

  GameMode? get currentMode => _currentMode;
  ModeConfig? get currentConfig => _currentConfig;
  ColonySimulation? get simulation => _simulation;
  PlayerProgress get playerProgress => _playerProgress;
  bool get isLoading => _isLoading;
  bool get canWin => _currentConfig?.winCondition != null;
  bool get canLose => _currentConfig?.loseCondition != null;
  bool get hasActiveSimulation => _simulation != null;

  @override
  void dispose() {
    _eventBus.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    if (_progressLoaded) {
      return;
    }
    _playerProgress = await _storage.loadPlayerProgress();
    _progressLoaded = true;
    notifyListeners();
  }

  Future<ColonySimulation> startMode(
    ModeConfig config, {
    SaveData? restoredState,
  }) async {
    await initialize();
    _setLoading(true);

    final simulation = ColonySimulation(
      config.simulationConfig,
      eventBus: _eventBus,
    );
    if (restoredState != null) {
      simulation.restoreFromSnapshot(restoredState.simulationState);
    } else {
      simulation.initialize();
      if (config is SandboxModeConfig && config.seed != null) {
        simulation.generateRandomWorld(seed: config.seed);
      } else {
        simulation.generateRandomWorld();
      }
    }

    _simulation = simulation;
    _currentConfig = config;
    _currentMode = config.mode;

    _eventBus.emit(GameModeChangedEvent(mode: config.mode));
    _eventBus.emit(SimulationLifecycleEvent.starting(mode: config.mode));

    _setLoading(false);
    notifyListeners();
    return simulation;
  }

  Future<void> endMode({bool save = true}) async {
    final mode = _currentMode;
    if (mode == null) {
      return;
    }
    if (save && (_currentConfig?.allowSave ?? false)) {
      await saveCurrentGame();
    }
    _simulation = null;
    _currentConfig = null;
    _currentMode = null;
    _eventBus.emit(SimulationLifecycleEvent.ended(mode: mode));
    notifyListeners();
  }

  Future<void> restartMode() async {
    final config = _currentConfig;
    if (config == null) {
      return;
    }
    await endMode(save: false);
    await startMode(config);
  }

  Future<bool> saveCurrentGame() async {
    final simulation = _simulation;
    final config = _currentConfig;
    if (simulation == null || config == null || !config.allowSave) {
      return false;
    }
    final snapshot = simulation.toSnapshot();
    final save = SaveData(
      mode: config.mode,
      savedAt: DateTime.now(),
      modeData: config.toJson(),
      playerProgress: _playerProgress,
      simulationState: snapshot,
    );
    await _storage.saveModeState(save);
    await _storage.savePlayerProgress(_playerProgress);
    return true;
  }

  Future<bool> loadSavedGame(GameMode mode) async {
    final save = await _storage.loadModeState(mode);
    if (save == null) {
      return false;
    }
    final config = modeConfigFromJson(save.modeData);
    await startMode(config, restoredState: save);
    return true;
  }

  Future<void> deleteSave(GameMode mode) async {
    await _storage.deleteModeState(mode);
  }

  Future<bool> hasSavedGame(GameMode mode) {
    return _storage.hasModeState(mode);
  }

  bool checkWinCondition() {
    final simulation = _simulation;
    final winCondition = _currentConfig?.winCondition;
    if (simulation == null || winCondition == null) {
      return false;
    }
    return winCondition.evaluate(simulation);
  }

  bool checkLoseCondition() {
    final simulation = _simulation;
    final loseCondition = _currentConfig?.loseCondition;
    if (simulation == null || loseCondition == null) {
      return false;
    }
    return loseCondition.evaluate(simulation);
  }

  void updatePlayerProgress(PlayerProgress progress, {bool persist = true}) {
    _playerProgress = progress;
    if (persist) {
      _storage.savePlayerProgress(progress);
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    _isLoading = value;
    notifyListeners();
  }
}
