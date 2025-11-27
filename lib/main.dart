import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/game/ant_world_game.dart';
import 'src/progression/progression_service.dart';
import 'src/progression/unlockables.dart';
import 'src/services/ad_service.dart';
import 'src/services/analytics_service.dart';
import 'src/simulation/colony_simulation.dart';
import 'src/simulation/simulation_config.dart';
import 'src/state/simulation_storage.dart';
import 'src/ui/ant_gallery_page.dart';
import 'src/ui/ant_hud.dart';
import 'src/ui/mobile_hud.dart';
import 'src/ui/widgets/banner_ad_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AdService.instance.initialize();
  await ProgressionService.instance.load();
  runApp(const AntWorldApp());
}

class AntWorldApp extends StatefulWidget {
  const AntWorldApp({super.key});

  @override
  State<AntWorldApp> createState() => _AntWorldAppState();
}

enum _AppScreen { menu, playing, antGallery }

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

    Widget body;
    if (_screen == _AppScreen.playing && _simulation != null && _game != null) {
      body = _buildGameView();
    } else if (_screen == _AppScreen.antGallery) {
      body = _buildAntGallery();
    } else {
      body = _buildMenu();
    }

    return MaterialApp(
      title: 'AntWorld',
      theme: theme,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _buildGameView() {
    final sim = _simulation!;
    final game = _game!;

    // Use MobileHud on iOS/Android, AntHud on desktop/web
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    // Build the game widget with appropriate gesture handling
    Widget gameWidget = GameWidget(game: game, focusNode: _focusNode, autofocus: true);

    if (isMobile) {
      // Mobile: Use GestureDetector for pinch-to-zoom and two-finger pan
      gameWidget = GestureDetector(
        onScaleStart: (details) {
          game.onPinchStart();
        },
        onScaleUpdate: (details) {
          // Calculate pan delta from focal point movement
          final focalDelta = details.focalPointDelta;
          game.onPinchUpdate(details.scale, focalDelta);
        },
        onScaleEnd: (details) {
          // Nothing special needed
        },
        child: gameWidget,
      );
    } else {
      // Desktop: Use Listener for trackpad/mouse wheel
      gameWidget = Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;

            if (isZoomModifier) {
              final zoomDelta = -event.scrollDelta.dy * 0.003;
              game.setZoom(game.zoomFactor + zoomDelta);
            } else {
              game.addPan(-event.scrollDelta.dx, -event.scrollDelta.dy);
            }
          } else if (event is PointerScaleEvent) {
            game.setZoom(game.zoomFactor * event.scale);
          }
        },
        child: gameWidget,
      );
    }

    return Stack(
      children: [
        gameWidget,
        if (isMobile)
          MobileHud(
            key: ValueKey(sim),
            simulation: sim,
            game: game,
            storage: _storage,
            onQuitToMenu: _quitToMenu,
          )
        else
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
    final progression = ProgressionService.instance;
    final maxColonies = getMaxColoniesForLevel(progression.level);

    // Ensure selected colony count is valid for current level
    if (_selectedColonyCount > maxColonies) {
      _selectedColonyCount = maxColonies;
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AntWorld',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  // Level indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Level ${progression.level}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: LinearProgressIndicator(
                            value: progression.levelProgress,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.amber),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Colony count selector (gated)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Colonies: '),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _selectedColonyCount,
                        items: List.generate(maxColonies, (i) => i + 1).map((count) {
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
                      if (maxColonies < 4) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Unlock more colonies by leveling up',
                          child: Icon(
                            Icons.lock,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
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
                        : Text(
                            'Start New Colony ($_selectedColonyCount ${_selectedColonyCount == 1 ? "colony" : "colonies"})',
                          ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loading ? null : _continueGame,
                    child: const Text('Continue Last Colony'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _screen = _AppScreen.antGallery),
                    icon: const Icon(Icons.pets_outlined),
                    label: const Text('View Ant Types'),
                  ),
                  if (_menuError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _menuError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  // Show next unlock hint
                  const SizedBox(height: 16),
                  _buildNextUnlockHint(progression),
                ],
              ),
            ),
          ),
        ),
        // Banner ad at bottom of menu
        const BannerAdWidget(),
      ],
    );
  }

  Widget _buildNextUnlockHint(ProgressionService progression) {
    final nextUnlock = getNextUnlockable(progression.level);
    if (nextUnlock == null) {
      return const Text(
        'All features unlocked!',
        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
      );
    }
    return Text(
      'Level ${nextUnlock.requiredLevel}: ${nextUnlock.name}',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
      ),
    );
  }

  Widget _buildAntGallery() {
    return AntGalleryPage(
      onBack: () => setState(() => _screen = _AppScreen.menu),
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

    // Track game start and trigger potential interstitial ad
    AnalyticsService.instance.logGameStart(
      colonyCount: _selectedColonyCount,
      mapCols: simulation.config.cols,
      mapRows: simulation.config.rows,
    );
    AnalyticsService.instance.setUserColonyPreference(_selectedColonyCount);
    AdService.instance.onGameStart();
    ProgressionService.instance.onGameStarted();

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
