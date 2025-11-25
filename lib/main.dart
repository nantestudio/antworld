import 'package:firebase_core/firebase_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/game/ant_world_game.dart';
import 'src/services/analytics_service.dart';
import 'src/simulation/colony_simulation.dart';
import 'src/simulation/simulation_config.dart';
import 'src/state/simulation_storage.dart';
import 'src/ui/ant_hud.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AntWorldApp());
}

class AntWorldApp extends StatefulWidget {
  const AntWorldApp({super.key});

  @override
  State<AntWorldApp> createState() => _AntWorldAppState();
}

enum _AppScreen { menu, playing }

class _AntWorldAppState extends State<AntWorldApp> {
  ColonySimulation? _simulation;
  AntWorldGame? _game;
  late final FocusNode _focusNode;
  late final SimulationStorage _storage;
  _AppScreen _screen = _AppScreen.menu;
  bool _loading = false;
  String? _menuError;
  int _selectedColonyCount = 2;

  @override
  void initState() {
    super.initState();
    _storage = SimulationStorage();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.greenAccent,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Silkscreen', // Pixel-style font
    );

    return MaterialApp(
      title: 'AntWorld',
      theme: theme,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _screen == _AppScreen.playing &&
                  _simulation != null &&
                  _game != null
              ? _buildGameView()
              : _buildMenu(),
        ),
      ),
    );
  }

  Offset _scaleStartFocalPoint = Offset.zero;

  Widget _buildGameView() {
    final sim = _simulation!;
    final game = _game!;
    return Stack(
      children: [
        GestureDetector(
          onScaleStart: (details) {
            _scaleStartFocalPoint = details.focalPoint;
            game.onPinchStart();
          },
          onScaleUpdate: (details) {
            final delta = details.focalPoint - _scaleStartFocalPoint;
            game.onPinchUpdate(details.scale, delta);
          },
          child: GameWidget(
            game: game,
            focusNode: _focusNode,
            autofocus: true,
          ),
        ),
        AntHud(
          key: ValueKey(sim),
          simulation: sim,
          game: game,
          storage: _storage,
          onQuitToMenu: _quitToMenu,
        ),
      ],
    );
  }

  Widget _buildMenu() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'AntWorld',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // Colony count selector
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Colonies: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedColonyCount,
                  items: [1, 2, 3, 4].map((count) {
                    return DropdownMenuItem(
                      value: count,
                      child: Text('$count'),
                    );
                  }).toList(),
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedColonyCount = value);
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _startNewGame,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Start New Colony ($_selectedColonyCount ${_selectedColonyCount == 1 ? "colony" : "colonies"})'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loading ? null : _continueGame,
              child: const Text('Continue Last Colony'),
            ),
            if (_menuError != null) ...[
              const SizedBox(height: 16),
              Text(
                _menuError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startNewGame() async {
    setState(() {
      _loading = true;
      _menuError = null;
    });

    final config = defaultSimulationConfig.copyWith(
      colonyCount: _selectedColonyCount,
    );
    final simulation = ColonySimulation(config);
    simulation.initialize();
    simulation.generateRandomWorld();
    final game = AntWorldGame(simulation);

    // Track game start
    AnalyticsService.instance.logGameStart(
      colonyCount: _selectedColonyCount,
      mapCols: simulation.config.cols,
      mapRows: simulation.config.rows,
    );
    AnalyticsService.instance.setUserColonyPreference(_selectedColonyCount);

    setState(() {
      _simulation = simulation;
      _game = game;
      _screen = _AppScreen.playing;
      _loading = false;
    });
  }

  Future<void> _continueGame() async {
    setState(() {
      _loading = true;
      _menuError = null;
    });
    final simulation = ColonySimulation(defaultSimulationConfig);
    final restored = await _storage.restore(simulation);
    if (!mounted) {
      return;
    }
    if (!restored) {
      setState(() {
        _loading = false;
        _menuError = 'No saved colony found';
      });
      return;
    }
    final game = AntWorldGame(simulation);

    // Track game load
    AnalyticsService.instance.logGameLoad(
      daysPassed: simulation.daysPassed.value,
      totalFood: simulation.foodCollected.value,
      antCount: simulation.ants.length,
    );

    setState(() {
      _simulation = simulation;
      _game = game;
      _screen = _AppScreen.playing;
      _loading = false;
    });
  }

  void _quitToMenu() {
    // Clear references to allow garbage collection
    setState(() {
      _simulation = null;
      _game = null;
      _screen = _AppScreen.menu;
    });
  }
}
