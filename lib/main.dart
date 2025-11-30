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
import 'src/core/level_catalog.dart';
import 'src/core/mode_config.dart';
import 'src/game/ant_world_game.dart';
import 'src/progression/daily_goal_service.dart';
import 'src/progression/progression_service.dart';
import 'src/progression/unlockables.dart';
import 'src/services/ad_service.dart';
import 'src/services/analytics_service.dart';
import 'src/services/cosmetics_service.dart';
import 'src/services/idle_progress_service.dart';
import 'src/simulation/colony_simulation.dart';
import 'src/simulation/simulation_config.dart';
import 'src/ui/ant_gallery_page.dart';
import 'src/ui/mobile_hud.dart';
import 'src/ui/widgets/banner_ad_widget.dart';
import 'src/ui/widgets/level_preview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AdService.instance.initialize();
  await ProgressionService.instance.load();
  await CosmeticsService.instance.load();
  await DailyGoalService.instance.load();
  await IdleProgressService.instance.load();
  runApp(const AntWorldApp());
}

class AntWorldApp extends StatefulWidget {
  const AntWorldApp({super.key});

  @override
  State<AntWorldApp> createState() => _AntWorldAppState();
}

enum _AppScreen { menu, playing, antGallery, settings }

class _AntWorldAppState extends State<AntWorldApp> with WidgetsBindingObserver {
  ColonySimulation? _simulation;
  AntWorldGame? _game;
  late final FocusNode _focusNode;
  late final GameStateManager _gameStateManager;
  _AppScreen _screen = _AppScreen.menu;
  bool _loading = false;
  String? _menuError;
  bool _hasSandboxSave = false;
  bool _claimingIdle = false;
  late final VoidCallback _idleListener;
  late final VoidCallback _goalsListener;
  String _selectedCampaignId = 'trailhead';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gameStateManager = GameStateManager();
    _focusNode = FocusNode();
    _idleListener = () {
      if (mounted) setState(() {});
    };
    _goalsListener = () {
      if (mounted) setState(() {});
    };
    IdleProgressService.instance.addListener(_idleListener);
    DailyGoalService.instance.addListener(_goalsListener);
    IdleProgressService.instance.computePendingReward();
    _refreshSandboxSaveState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    IdleProgressService.instance.removeListener(_idleListener);
    DailyGoalService.instance.removeListener(_goalsListener);
    _focusNode.dispose();
    _gameStateManager.dispose();
    // Ensure screen can sleep when app closes
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      IdleProgressService.instance.recordSession(
        mode: _gameStateManager.currentMode ?? GameMode.sandbox,
        simulation: _simulation,
      );
    } else if (state == AppLifecycleState.resumed) {
      IdleProgressService.instance.computePendingReward();
    }
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

    // Build the game widget with appropriate gesture handling
    Widget gameWidget = GameWidget(
      game: game,
      focusNode: _focusNode,
      autofocus: true,
    );

    gameWidget = GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
      onScaleStart: (_) {
        game.onPinchStart();
      },
      onScaleUpdate: (details) {
        game.onPinchUpdate(details.scale, details.focalPointDelta);
      },
      child: gameWidget,
    );

    if (!isTouchPlatform || isTabletLayout) {
      // Desktop: Use Listener for trackpad/mouse wheel
      gameWidget = Listener(
        onPointerSignal: (event) {
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
        },
        child: gameWidget,
      );
    }

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
    final progression = ProgressionService.instance;
    final idle = IdleProgressService.instance;
    final pendingIdle = idle.pendingReward;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1D0F), Color(0xFF0D0F16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeroHeader(progression),
                      const SizedBox(height: 12),
                      _buildCampaignSelector(),
                      const SizedBox(height: 20),
                      _buildPrimaryActions(),
                      if (_menuError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _menuError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildIdleRewardCard(pendingIdle, idle),
                      const SizedBox(height: 12),
                      _buildGoalsCard(DailyGoalService.instance),
                      const SizedBox(height: 16),
                      _buildMenuLinks(),
                      const SizedBox(height: 12),
                      _buildNextUnlockHint(progression),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Banner ad at bottom of menu
          const BannerAdWidget(),
        ],
      ),
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

  Widget _buildHeroHeader(ProgressionService progression) {
    final streak = DailyGoalService.instance.currentStreak;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF163021), Color(0xFF0F1C18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AntWorld',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Mesmerizing colonies. Build, observe, relax.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 6),
              Text(
                'Level ${progression.level}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: progression.levelProgress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Daily streak: $streak',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Total XP: ${progression.totalXP}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActions() {
    final canContinue = _hasSandboxSave;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _startCampaign,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start Campaign'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton.tonal(
                onPressed: _loading ? null : _startSandbox,
                child: const Text('Launch Sandbox'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _loading || !canContinue ? null : _continueGame,
                child: const Text('Continue Last Colony'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleRewardCard(IdleReward? reward, IdleProgressService idle) {
    final hasReward = reward != null;
    final awayLabel = reward != null
        ? _formatDuration(reward.awayDuration)
        : null;
    final pendingFood = reward?.food ?? 0;
    final pendingXp = reward?.xp ?? 0;
    final banked = idle.bankedFood;
    final totalFood = banked + pendingFood;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top, color: Colors.greenAccent),
              const SizedBox(width: 8),
              const Text(
                'Idle stash',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (awayLabel != null)
                Text(
                  'Away $awayLabel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _statPill(
                icon: Icons.restaurant,
                label: 'Food ready',
                value: '+$pendingFood',
              ),
              _statPill(icon: Icons.explore, label: 'Banked', value: '$banked'),
              _statPill(icon: Icons.bolt, label: 'XP', value: '+$pendingXp'),
              _statPill(
                icon: Icons.grain,
                label: 'Total drop',
                value: '$totalFood',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: (!_claimingIdle && hasReward)
                    ? _claimIdleReward
                    : null,
                child: _claimingIdle
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(hasReward ? 'Claim & bank' : 'No new idle reward'),
              ),
              Text(
                'Food drops near the nest when you start a run.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsCard(DailyGoalService goals) {
    final items = goals.goals;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, color: Colors.lightBlueAccent),
              const SizedBox(width: 8),
              const Text(
                'Daily goals',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'Streak ${goals.currentStreak}d',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text('New goals arrive each day.')
          else ...[
            for (final goal in items) ...[
              _buildGoalRow(goal),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _loading ? null : goals.claimCompletedGoals,
                child: const Text('Claim completed XP'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuLinks() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => setState(() => _screen = _AppScreen.antGallery),
          icon: const Icon(Icons.pets_outlined),
          label: const Text('Ant Gallery'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _startTutorial,
          icon: const Icon(Icons.school),
          label: const Text('Tutorial'),
        ),
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => setState(() => _screen = _AppScreen.settings),
          icon: const Icon(Icons.settings),
          label: const Text('Settings & Cosmetics'),
        ),
      ],
    );
  }

  Widget _buildGoalRow(DailyGoal goal) {
    final progress = goal.target == 0 ? 0.0 : goal.progress / goal.target;
    final clamped = progress.clamp(0.0, 1.0);
    final done = goal.isComplete;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: done ? Colors.greenAccent : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                goal.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: done ? Colors.greenAccent : Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+${goal.rewardXp} XP',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                done ? 'Complete' : '${goal.progress}/${goal.target}',
                style: TextStyle(
                  color: done
                      ? Colors.greenAccent
                      : Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            goal.description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: clamped,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              done ? Colors.greenAccent : Colors.lightBlueAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCosmeticsCard(ProgressionService progression) {
    final service = CosmeticsService.instance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, color: Colors.pinkAccent),
              const SizedBox(width: 8),
              const Text(
                'Ant cosmetics',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'Colony 0 only',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: service.palettes
                .map(
                  (palette) => _buildPaletteChip(palette, progression, service),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteChip(
    CosmeticPalette palette,
    ProgressionService progression,
    CosmeticsService service,
  ) {
    final unlocked =
        palette.requiredLevel == null ||
        progression.level >= (palette.requiredLevel ?? 1);
    final isSelected = service.selectedPaletteId == palette.id;
    return GestureDetector(
      onTap: !_loading && unlocked
          ? () async {
              await service.selectPalette(palette.id);
              setState(() {});
            }
          : null,
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
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: unlocked
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                if (palette.description.isNotEmpty)
                  Text(
                    palette.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                if (!unlocked && palette.requiredLevel != null)
                  Text(
                    'Unlock at level ${palette.requiredLevel}',
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
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

  Widget _statPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      return '${hours}h ${minutes}m';
    }
    return '${duration.inMinutes}m';
  }

  Widget _buildAntGallery() {
    return AntGalleryPage(
      onBack: () => setState(() => _screen = _AppScreen.menu),
    );
  }

  Widget _buildSettings() {
    final progression = ProgressionService.instance;
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
              'Settings & Cosmetics',
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
                _buildCosmeticsCard(progression),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'More settings coming soon: audio levels, camera pan/zoom sensitivity, and HUD layout.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCampaignSelector() {
    final info = campaignLevelInfo[_selectedCampaignId];
    final layout = campaignLayoutById(_selectedCampaignId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Campaign Levels',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: campaignLevelInfo.values.map((entry) {
            final isSelected = entry.id == _selectedCampaignId;
            return ChoiceChip(
              selected: isSelected,
              label: Text(entry.title),
              onSelected: (value) {
                if (value) {
                  setState(() => _selectedCampaignId = entry.id);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (info != null) ...[
          Text(
            info.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            info.summary,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          ),
        ],
        const SizedBox(height: 8),
        if (layout != null)
          LevelPreview(key: ValueKey(layout.id), layout: layout),
      ],
    );
  }

  Future<void> _startCampaign() async {
    await _beginGame(_campaignConfig());
  }

  Future<void> _startTutorial() async {
    await _beginGame(_tutorialConfig());
  }

  Future<void> _startSandbox() async {
    await _beginGame(const SandboxModeConfig());
  }

  ModeConfig _campaignConfig() {
    final layout = campaignLayoutById(_selectedCampaignId);
    final baseConfig = defaultSimulationConfig.copyWith(
      colonyCount: layout?.colonyCount ?? 1,
      cols: layout?.cols ?? defaultSimulationConfig.cols,
      rows: layout?.rows ?? defaultSimulationConfig.rows,
      startingAnts: _selectedCampaignId == 'trailhead'
          ? 60
          : defaultSimulationConfig.startingAnts,
      foodPerNewAnt: _selectedCampaignId == 'trailhead'
          ? 8
          : defaultSimulationConfig.foodPerNewAnt,
    );
    return CampaignLevelConfig(
      levelId: _selectedCampaignId,
      objective: const LevelObjective(
        id: 'gather',
        description: 'Collect 2000 food and survive 8 days.',
      ),
      win: WinCondition(
        id: 'food200',
        description: 'Reach 2000 food and day 8',
        evaluator: (sim) =>
            sim.foodCollected.value >= 2000 && sim.daysPassed.value >= 8,
      ),
      config: baseConfig,
      layoutOverride: layout,
    );
  }

  ModeConfig _tutorialConfig() {
    return CampaignLevelConfig(
      levelId: 'tutorial',
      objective: const LevelObjective(
        id: 'tutorial-basics',
        description: 'Follow trails, dig a room, and stockpile 50 food.',
      ),
      starConditions: const [
        StarCondition(
          id: 'food',
          description: 'Collect 50 food',
          threshold: 50,
        ),
        StarCondition(id: 'days', description: 'Survive 2 days', threshold: 2),
      ],
      config: defaultSimulationConfig.copyWith(
        cols: 80,
        rows: 60,
        colonyCount: 1,
        startingAnts: 90,
        antSpeed: defaultSimulationConfig.antSpeed * 0.9,
      ),
      win: WinCondition(
        id: 'tutorial-win',
        description: 'Gather 50 food',
        evaluator: (sim) => sim.foodCollected.value >= 50,
      ),
    );
  }

  Future<void> _beginGame(ModeConfig config) async {
    setState(() {
      _loading = true;
      _menuError = null;
    });

    try {
      final simulation = await _gameStateManager.startMode(config);
      final game = AntWorldGame(simulation);

      // Track game start and trigger potential interstitial ad
      AnalyticsService.instance.logGameStart(
        colonyCount: simulation.config.colonyCount,
        mapCols: simulation.config.cols,
        mapRows: simulation.config.rows,
      );
      AnalyticsService.instance.setUserColonyPreference(
        simulation.config.colonyCount,
      );
      AdService.instance.onGameStart();
      ProgressionService.instance.onGameStarted();

      if (!mounted) {
        return;
      }
      setState(() {
        _simulation = simulation;
        _game = game;
        _screen = _AppScreen.playing;
        _loading = false;
      });
      // Keep screen awake while playing
      WakelockPlus.enable();
    } catch (error) {
      if (!mounted) {
        return;
      }
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

    if (!mounted) {
      return;
    }

    if (!restored || _gameStateManager.simulation == null) {
      setState(() {
        _loading = false;
        _menuError = 'No saved colony found';
      });
      return;
    }

    final simulation = _gameStateManager.simulation!;
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
    // Keep screen awake while playing
    WakelockPlus.enable();
  }

  Future<void> _claimIdleReward() async {
    setState(() {
      _claimingIdle = true;
      _menuError = null;
    });
    try {
      await IdleProgressService.instance.computePendingReward();
      IdleProgressService.instance.claimPendingReward();
    } catch (error) {
      setState(() => _menuError = 'Could not claim idle reward: $error');
    } finally {
      if (mounted) {
        setState(() => _claimingIdle = false);
      }
    }
  }

  Future<void> _quitToMenu() async {
    await _gameStateManager.endMode(save: false);
    // Allow screen to sleep again
    WakelockPlus.disable();
    // Clear references to allow garbage collection
    setState(() {
      _simulation = null;
      _game = null;
      _screen = _AppScreen.menu;
    });
    _refreshSandboxSaveState();
  }

  Future<void> _refreshSandboxSaveState() async {
    final hasSave = await _gameStateManager.hasSavedGame(GameMode.sandbox);
    if (!mounted) {
      return;
    }
    setState(() {
      _hasSandboxSave = hasSave;
    });
  }
}
