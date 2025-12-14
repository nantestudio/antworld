import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'firebase_options.dart';
import 'src/core/game_mode.dart';
import 'src/core/game_state_manager.dart';
import 'src/core/mode_config.dart';
import 'src/game/ant_world_game.dart';
import 'src/services/analytics_service.dart';
import 'src/services/cosmetics_service.dart';
import 'src/simulation/colony_simulation.dart';
import 'src/ui/ant_gallery_page.dart';
import 'src/ui/mobile_hud.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CosmeticsService.instance.load();

  runApp(const AntWorldApp());
}

class AntWorldApp extends StatefulWidget {
  const AntWorldApp({super.key});

  @override
  State<AntWorldApp> createState() => _AntWorldAppState();
}

enum _AppScreen { menu, playing, antGallery, settings }

class _AntWorldAppState extends State<AntWorldApp> {
  ColonySimulation? _simulation;
  AntWorldGame? _game;
  late final FocusNode _focusNode;
  late final GameStateManager _gameStateManager;
  _AppScreen _screen = _AppScreen.menu;
  bool _loading = false;
  String? _menuError;
  bool _hasSandboxSave = false;

  // Pointer tracking for gesture handling (used for state cleanup on gesture end)
  final Set<int> _activePointers = {};

  @override
  void initState() {
    super.initState();
    _gameStateManager = GameStateManager();
    _focusNode = FocusNode();
    _refreshSandboxSaveState();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _gameStateManager.dispose();
    WakelockPlus.disable();
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
      fontFamily: 'Silkscreen',
    );

    Widget body;
    if (_screen == _AppScreen.playing && _simulation != null && _game != null) {
      body = _buildGameView();
    } else if (_screen == _AppScreen.antGallery) {
      body = _buildAntGallery();
    } else if (_screen == _AppScreen.settings) {
      body = _buildSettings();
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
    final isTouchPlatform = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    final shortestSide = _logicalShortestSide();
    final isTabletLayout = shortestSide >= 700;
    final useMobileHud = true;
    final isWideHud = !isTouchPlatform || isTabletLayout;

    Widget gameWidget = GameWidget(
      game: game,
      focusNode: _focusNode,
      autofocus: true,
    );

    // Wrap with GestureDetector for pan/zoom handling
    gameWidget = GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
      onScaleStart: (details) {
        game.onPinchStart(details.pointerCount);
      },
      onScaleUpdate: (details) {
        game.onPinchUpdate(
          details.scale,
          details.focalPointDelta,
          details.pointerCount,
        );
      },
      onScaleEnd: (details) {
        game.onPinchEnd();
        // Clear pointers on gesture end to reset state
        _activePointers.clear();
      },
      child: gameWidget,
    );

    // Wrap with Listener to track active pointer count
    // This enables proper gesture disambiguation
    gameWidget = Listener(
      onPointerDown: (event) {
        _activePointers.add(event.pointer);
      },
      onPointerUp: (event) {
        _activePointers.remove(event.pointer);
      },
      onPointerCancel: (event) {
        _activePointers.remove(event.pointer);
      },
      onPointerSignal: (!isTouchPlatform || isTabletLayout)
          ? (event) {
              // Scroll wheel / trackpad handling for desktop/tablet
              if (event is PointerScrollEvent) {
                final isZoomModifier =
                    HardwareKeyboard.instance.isControlPressed ||
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
            }
          : null,
      child: gameWidget,
    );

    return Stack(
      children: [
        gameWidget,
        if (useMobileHud)
          MobileHud(
            key: ValueKey(sim),
            simulation: sim,
            game: game,
            gameStateManager: _gameStateManager,
            onQuitToMenu: () => _quitToMenu(),
            onGameSaved: _refreshSandboxSaveState,
            isWideLayout: isWideHud,
          ),
      ],
    );
  }

  double _logicalShortestSide() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
    return math.min(logicalWidth, logicalHeight);
  }

  Widget _buildMenu() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1D0F), Color(0xFF0D0F16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'AntWorld',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Build, observe, relax.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _startSandbox,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('New Game'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _loading || !_hasSandboxSave
                        ? null
                        : _continueGame,
                    child: const Text('Continue'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _screen = _AppScreen.settings),
                    child: const Text('Settings'),
                  ),
                ),
                if (_menuError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _menuError!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _screen = _AppScreen.antGallery),
                  child: const Text('Ant Gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAntGallery() {
    return AntGalleryPage(
      onBack: () => setState(() => _screen = _AppScreen.menu),
    );
  }

  Widget _buildSettings() {
    final service = CosmeticsService.instance;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _screen = _AppScreen.menu),
            ),
            const SizedBox(width: 4),
            const Text(
              'Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.pinkAccent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.palette, color: Colors.pinkAccent),
                          SizedBox(width: 8),
                          Text(
                            'Ant Cosmetics',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: service.palettes
                            .map((p) => _buildPaletteChip(p, service))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'More settings coming soon: audio levels, camera sensitivity, HUD layout.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaletteChip(CosmeticPalette palette, CosmeticsService service) {
    final isSelected = service.selectedPaletteId == palette.id;
    return GestureDetector(
      onTap: () async {
        await service.selectPalette(palette.id);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? Colors.pinkAccent
                : Colors.white.withValues(alpha: 0.2),
          ),
          color: Colors.white.withValues(alpha: 0.03),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _swatch(palette.body),
            _swatch(palette.carrying),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  palette.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (palette.description.isNotEmpty)
                  Text(
                    palette.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, color: Colors.pinkAccent, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _swatch(Color color) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  Future<void> _startSandbox() async {
    await _beginGame(const SandboxModeConfig());
  }

  Future<void> _beginGame(ModeConfig config) async {
    setState(() {
      _loading = true;
      _menuError = null;
    });

    try {
      final simulation = await _gameStateManager.startMode(config);
      final game = AntWorldGame(simulation);

      AnalyticsService.instance.logGameStart(
        colonyCount: simulation.config.colonyCount,
        mapCols: simulation.config.cols,
        mapRows: simulation.config.rows,
      );
      AnalyticsService.instance.setUserColonyPreference(
        simulation.config.colonyCount,
      );

      if (!mounted) return;
      setState(() {
        _simulation = simulation;
        _game = game;
        _screen = _AppScreen.playing;
        _loading = false;
      });
      WakelockPlus.enable();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _menuError = 'Failed to start game: $error';
      });
    }
  }

  Future<void> _continueGame() async {
    setState(() {
      _loading = true;
      _menuError = null;
    });
    final restored = await _gameStateManager.loadSavedGame(GameMode.sandbox);

    if (!mounted) return;

    if (!restored || _gameStateManager.simulation == null) {
      setState(() {
        _loading = false;
        _menuError = 'No saved colony found';
      });
      return;
    }

    final simulation = _gameStateManager.simulation!;
    final game = AntWorldGame(simulation);

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
    WakelockPlus.enable();
  }

  Future<void> _quitToMenu() async {
    await _gameStateManager.endMode(save: false);
    WakelockPlus.disable();
    setState(() {
      _simulation = null;
      _game = null;
      _screen = _AppScreen.menu;
    });
    _refreshSandboxSaveState();
  }

  Future<void> _refreshSandboxSaveState() async {
    final hasSave = await _gameStateManager.hasSavedGame(GameMode.sandbox);
    if (!mounted) return;
    setState(() {
      _hasSandboxSave = hasSave;
    });
  }
}
