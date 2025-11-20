import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'src/game/ant_world_game.dart';
import 'src/simulation/colony_simulation.dart';
import 'src/simulation/simulation_config.dart';
import 'src/state/simulation_storage.dart';
import 'src/ui/ant_hud.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AntWorldApp());
}

class AntWorldApp extends StatefulWidget {
  const AntWorldApp({super.key});

  @override
  State<AntWorldApp> createState() => _AntWorldAppState();
}

class _AntWorldAppState extends State<AntWorldApp> {
  late final ColonySimulation _simulation;
  late final AntWorldGame _game;
  late final FocusNode _focusNode;
  late final SimulationStorage _storage;

  @override
  void initState() {
    super.initState();
    _storage = SimulationStorage();
    _simulation = ColonySimulation(defaultSimulationConfig)..initialize();
    _game = AntWorldGame(_simulation);
    _focusNode = FocusNode();
    _restoreWorld();
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
    );

    return MaterialApp(
      title: 'AntWorld',
      theme: theme,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              GameWidget(
                game: _game,
                focusNode: _focusNode,
                autofocus: true,
              ),
              AntHud(
                simulation: _simulation,
                game: _game,
                storage: _storage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restoreWorld() async {
    final restored = await _storage.restore(_simulation);
    if (!mounted || !restored) {
      return;
    }
    _game.invalidateTerrainLayer();
    setState(() {});
  }
}
