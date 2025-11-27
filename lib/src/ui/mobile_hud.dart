import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../core/game_state_manager.dart';
import '../game/ant_world_game.dart';
import '../progression/progression_service.dart';
import '../progression/unlockables.dart';
import '../services/analytics_service.dart';
import '../simulation/ant.dart';
import '../simulation/colony_simulation.dart';
import 'widgets/native_ad_widget.dart';

/// Mobile-optimized HUD with bottom sheet controls and floating tools
class MobileHud extends StatefulWidget {
  const MobileHud({
    super.key,
    required this.simulation,
    required this.game,
    required this.gameStateManager,
    this.onQuitToMenu,
    this.onGameSaved,
  });

  final ColonySimulation simulation;
  final AntWorldGame game;
  final GameStateManager gameStateManager;
  final VoidCallback? onQuitToMenu;
  final VoidCallback? onGameSaved;

  @override
  State<MobileHud> createState() => _MobileHudState();
}

class _MobileHudState extends State<MobileHud> with TickerProviderStateMixin {
  bool _toolsExpanded = false;
  bool _saving = false;
  late AnimationController _toolsAnimController;

  // Haptic feedback helper
  Future<void> _haptic([
    HapticFeedbackType type = HapticFeedbackType.lightImpact,
  ]) async {
    if (Platform.isIOS || Platform.isAndroid) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        switch (type) {
          case HapticFeedbackType.lightImpact:
            Vibration.vibrate(duration: 10, amplitude: 40);
          case HapticFeedbackType.mediumImpact:
            Vibration.vibrate(duration: 20, amplitude: 80);
          case HapticFeedbackType.heavyImpact:
            Vibration.vibrate(duration: 30, amplitude: 128);
          case HapticFeedbackType.selection:
            Vibration.vibrate(duration: 5, amplitude: 20);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _toolsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _toolsAnimController.dispose();
    super.dispose();
  }

  void _toggleTools() {
    _haptic(HapticFeedbackType.selection);
    setState(() {
      _toolsExpanded = !_toolsExpanded;
      if (_toolsExpanded) {
        _toolsAnimController.forward();
      } else {
        _toolsAnimController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Top stats bar
          _buildTopBar(context),
          // Floating tool palette (right side)
          _buildToolPalette(context),
          // Bottom control bar
          _buildBottomBar(context),
          // Native ad at the very bottom
          _buildNativeAd(context),
          // Selected ant panel
          _buildSelectedAntPanel(context),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final sim = widget.simulation;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(color: Colors.black87),
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<void>(
            stream: Stream.periodic(const Duration(milliseconds: 500)),
            builder: (context, _) {
              return Row(
                children: [
                  // Day counter
                  _TopStatChip(
                    icon: Icons.wb_sunny,
                    value: 'Day ${sim.daysPassed.value}',
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  // Food for colony 0
                  _TopStatChip(
                    icon: Icons.restaurant,
                    value: '${sim.colony0Food.value}',
                    color: Colors.lightGreenAccent,
                  ),
                  const SizedBox(width: 8),
                  // Ant count
                  _TopStatChip(
                    icon: Icons.bug_report,
                    value: '${sim.antCount.value}',
                    color: Colors.cyanAccent,
                  ),
                  const Spacer(),
                  // Menu button
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => _showMenuSheet(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToolPalette(BuildContext context) {
    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main tool toggle button
          _ToolFab(
            icon: _toolsExpanded ? Icons.close : Icons.edit,
            onPressed: _toggleTools,
            isPrimary: true,
          ),
          // Expandable tools
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _toolsExpanded
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.game.editMode,
                        builder: (context, editMode, _) {
                          return _ToolFab(
                            icon: editMode ? Icons.lock_open : Icons.lock,
                            onPressed: () {
                              _haptic();
                              widget.game.editMode.value = !editMode;
                            },
                            isActive: editMode,
                            tooltip: editMode ? 'Lock' : 'Unlock editing',
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<BrushMode>(
                        valueListenable: widget.game.brushMode,
                        builder: (context, mode, _) {
                          return Column(
                            children: [
                              _ToolFab(
                                icon: Icons.construction,
                                onPressed: () {
                                  _haptic();
                                  widget.game.setBrushMode(BrushMode.dig);
                                },
                                isActive: mode == BrushMode.dig,
                                tooltip: 'Dig',
                              ),
                              const SizedBox(height: 8),
                              _ToolFab(
                                icon: Icons.fastfood,
                                onPressed: () {
                                  _haptic();
                                  widget.game.setBrushMode(BrushMode.food);
                                },
                                isActive: mode == BrushMode.food,
                                tooltip: 'Food',
                              ),
                              const SizedBox(height: 8),
                              _ToolFab(
                                icon: Icons.landscape,
                                onPressed: () {
                                  _haptic();
                                  widget.game.setBrushMode(BrushMode.rock);
                                },
                                isActive: mode == BrushMode.rock,
                                tooltip: 'Rock',
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 60, // Make room for native ad below
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(color: Colors.black87),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Pause/Play
                ValueListenableBuilder<bool>(
                  valueListenable: widget.simulation.paused,
                  builder: (context, isPaused, _) {
                    return _BottomBarButton(
                      icon: isPaused ? Icons.play_arrow : Icons.pause,
                      label: isPaused ? 'Play' : 'Pause',
                      onPressed: () {
                        _haptic(HapticFeedbackType.mediumImpact);
                        widget.simulation.togglePause();
                      },
                      color: isPaused ? Colors.green : Colors.orange,
                    );
                  },
                ),
                // Speed control
                _BottomBarButton(
                  icon: Icons.speed,
                  label: 'Speed',
                  onPressed: () => _showSpeedSheet(context),
                ),
                // Stats
                _BottomBarButton(
                  icon: Icons.bar_chart,
                  label: 'Stats',
                  onPressed: () => _showStatsSheet(context),
                ),
                // Settings
                _BottomBarButton(
                  icon: Icons.tune,
                  label: 'Settings',
                  onPressed: () => _showSettingsSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNativeAd(BuildContext context) {
    return const Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: NativeAdWidget(),
    );
  }

  Widget _buildSelectedAntPanel(BuildContext context) {
    return ValueListenableBuilder<Ant?>(
      valueListenable: widget.game.selectedAnt,
      builder: (context, ant, _) {
        if (ant == null) return const SizedBox.shrink();

        return Positioned(
          left: 12,
          bottom: MediaQuery.of(context).padding.bottom + 80,
          child: _MobileAntCard(
            ant: ant,
            simulation: widget.simulation,
            onClose: () {
              _haptic(HapticFeedbackType.selection);
              widget.game.clearSelection();
            },
          ),
        );
      },
    );
  }

  void _showMenuSheet(BuildContext context) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Save button
              ListTile(
                leading: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                title: Text(_saving ? 'Saving...' : 'Save Game'),
                onTap: _saving ? null : () => _saveGame(context),
              ),
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('Toggle Pheromones'),
                onTap: () {
                  final current = widget.simulation.pheromonesVisible.value;
                  widget.simulation.setPheromoneVisibility(!current);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_florist),
                title: const Text('Scatter Food'),
                onTap: () {
                  widget.simulation.scatterFood(clusters: 8, radius: 3);
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: const Text(
                  'Quit to Menu',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => _confirmQuit(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context) {
    _haptic();
    final progression = ProgressionService.instance;
    final maxSpeed = getMaxSpeedForLevel(progression.level);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Simulation Speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: widget.simulation.antSpeedMultiplier,
                builder: (context, multiplier, _) {
                  const double base = 0.2;
                  final display = (multiplier / base).clamp(1.0, 10.0);
                  return Column(
                    children: [
                      Text(
                        '${display.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: display.clamp(1.0, maxSpeed),
                        min: 1.0,
                        max: maxSpeed,
                        divisions: ((maxSpeed - 1) * 2).toInt(),
                        onChanged: (value) {
                          widget.simulation.setAntSpeedMultiplier(value * base);
                          AnalyticsService.instance.logSpeedChanged(
                            speedMultiplier: value,
                          );
                        },
                      ),
                      if (maxSpeed < 10.0)
                        Text(
                          'Unlock faster speeds by leveling up!',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Quick speed buttons
              Wrap(
                spacing: 8,
                children: [
                  _SpeedButton(
                    label: '1x',
                    speed: 1.0,
                    maxSpeed: maxSpeed,
                    sim: widget.simulation,
                  ),
                  _SpeedButton(
                    label: '2x',
                    speed: 2.0,
                    maxSpeed: maxSpeed,
                    sim: widget.simulation,
                  ),
                  _SpeedButton(
                    label: '3x',
                    speed: 3.0,
                    maxSpeed: maxSpeed,
                    sim: widget.simulation,
                  ),
                  _SpeedButton(
                    label: '5x',
                    speed: 5.0,
                    maxSpeed: maxSpeed,
                    sim: widget.simulation,
                  ),
                  _SpeedButton(
                    label: '10x',
                    speed: 10.0,
                    maxSpeed: maxSpeed,
                    sim: widget.simulation,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatsSheet(BuildContext context) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: _MobileStatsContent(simulation: widget.simulation),
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: _MobileSettingsContent(
              simulation: widget.simulation,
              game: widget.game,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveGame(BuildContext context) async {
    setState(() => _saving = true);
    final success = await widget.gameStateManager.saveCurrentGame();

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);

      if (success) {
        AnalyticsService.instance.logGameSaved(
          daysPassed: widget.simulation.daysPassed.value,
          antCount: widget.simulation.ants.length,
          totalFood: widget.simulation.foodCollected.value,
        );
        widget.onGameSaved?.call();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Game saved!' : 'Failed to save'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmQuit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit Game?'),
        content: const Text('Any unsaved progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Quit'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.pop(context); // Close menu sheet
      widget.simulation.prepareForNewWorld();
      widget.game.invalidateTerrainLayer();
      widget.onQuitToMenu?.call();
    }
  }
}

enum HapticFeedbackType { lightImpact, mediumImpact, heavyImpact, selection }

class _TopStatChip extends StatelessWidget {
  const _TopStatChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolFab extends StatelessWidget {
  const _ToolFab({
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.isActive = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isActive;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final button = SizedBox(
      width: isPrimary ? 48 : 40,
      height: isPrimary ? 48 : 40,
      child: FloatingActionButton(
        heroTag: null,
        elevation: isPrimary ? 4 : 2,
        backgroundColor: isActive
            ? colorScheme.primary
            : isPrimary
            ? colorScheme.primaryContainer
            : Colors.grey.shade800,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: isPrimary ? 24 : 20,
          color: isActive || isPrimary ? colorScheme.onPrimary : Colors.white70,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: color ?? Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.label,
    required this.speed,
    required this.maxSpeed,
    required this.sim,
  });

  final String label;
  final double speed;
  final double maxSpeed;
  final ColonySimulation sim;

  @override
  Widget build(BuildContext context) {
    final locked = speed > maxSpeed;
    const double base = 0.2;

    return ValueListenableBuilder<double>(
      valueListenable: sim.antSpeedMultiplier,
      builder: (context, multiplier, _) {
        final current = (multiplier / base).clamp(1.0, 10.0);
        final isActive = (current - speed).abs() < 0.1;

        return FilterChip(
          label: Text(label),
          selected: isActive,
          onSelected: locked
              ? null
              : (_) {
                  sim.setAntSpeedMultiplier(speed * base);
                  AnalyticsService.instance.logSpeedChanged(
                    speedMultiplier: speed,
                  );
                },
          avatar: locked ? const Icon(Icons.lock, size: 14) : null,
        );
      },
    );
  }
}

class _MobileAntCard extends StatelessWidget {
  const _MobileAntCard({
    required this.ant,
    required this.simulation,
    required this.onClose,
  });

  final Ant ant;
  final ColonySimulation simulation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: Stream.periodic(const Duration(milliseconds: 200)),
      builder: (context, _) {
        return Card(
          color: Colors.grey.shade900.withValues(alpha: 0.9),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bug_report,
                        size: 16,
                        color: ant.colonyId == 0 ? Colors.cyan : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_casteLabel(ant.caste)} #${ant.id}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _MiniStat('State', _stateLabel(ant)),
                  _MiniStat(
                    'Energy',
                    '${ant.energy.toInt()}/${simulation.config.energyCapacity.toInt()}',
                  ),
                  _MiniStat('HP', '${ant.hp.toInt()}/${ant.maxHp.toInt()}'),
                  if (ant.hasFood) _MiniStat('Carrying', 'Food'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _stateLabel(Ant ant) {
    switch (ant.state) {
      case AntState.forage:
        return 'Foraging';
      case AntState.returnHome:
        return 'Returning';
      case AntState.rest:
        return 'Resting';
    }
  }

  String _casteLabel(AntCaste caste) {
    switch (caste) {
      case AntCaste.worker:
        return 'Worker';
      case AntCaste.soldier:
        return 'Soldier';
      case AntCaste.nurse:
        return 'Nurse';
      case AntCaste.drone:
        return 'Drone';
      case AntCaste.princess:
        return 'Princess';
      case AntCaste.queen:
        return 'Queen';
      case AntCaste.larva:
        return 'Larva';
      case AntCaste.egg:
        return 'Egg';
      case AntCaste.builder:
        return 'Builder';
    }
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          Text(value, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _MobileStatsContent extends StatelessWidget {
  const _MobileStatsContent({required this.simulation});

  final ColonySimulation simulation;

  static const _colonyColors = [
    Color(0xFFF44336), // Red
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF2196F3), // Blue
    Color(0xFFFFFFFF), // White
  ];

  @override
  Widget build(BuildContext context) {
    final sim = simulation;
    final colonyCount = sim.config.colonyCount;

    return StreamBuilder<void>(
      stream: Stream.periodic(const Duration(milliseconds: 500)),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header
            Row(
              children: [
                Text(
                  'Day ${sim.daysPassed.value}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sim.antCount.value} ants',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Colony stats
            if (colonyCount >= 1)
              _ColonyCard(
                name: 'Colony 0',
                color: _colonyColors[0],
                food: sim.colony0Food.value,
                workers: sim.workerCount,
                soldiers: sim.soldierCount,
                nurses: sim.nurseCount,
                queens: sim.queenCount,
                larvae: sim.larvaCount,
                eggs: sim.eggCount,
              ),
            if (colonyCount >= 2) ...[
              const SizedBox(height: 12),
              _ColonyCard(
                name: 'Colony 1',
                color: _colonyColors[1],
                food: sim.colony1Food.value,
                workers: sim.enemy1WorkerCount,
                soldiers: sim.enemy1SoldierCount,
                nurses: sim.enemy1NurseCount,
                queens: sim.enemy1QueenCount,
                larvae: sim.enemy1LarvaCount,
                eggs: sim.enemy1EggCount,
              ),
            ],
            if (colonyCount >= 3) ...[
              const SizedBox(height: 12),
              _ColonyCard(
                name: 'Colony 2',
                color: _colonyColors[2],
                food: sim.colony2Food.value,
                workers: sim.enemy2WorkerCount,
                soldiers: sim.enemy2SoldierCount,
                nurses: sim.enemy2NurseCount,
                queens: sim.enemy2QueenCount,
                larvae: sim.enemy2LarvaCount,
                eggs: sim.enemy2EggCount,
              ),
            ],
            if (colonyCount >= 4) ...[
              const SizedBox(height: 12),
              _ColonyCard(
                name: 'Colony 3',
                color: _colonyColors[3],
                food: sim.colony3Food.value,
                workers: sim.enemy3WorkerCount,
                soldiers: sim.enemy3SoldierCount,
                nurses: sim.enemy3NurseCount,
                queens: sim.enemy3QueenCount,
                larvae: sim.enemy3LarvaCount,
                eggs: sim.enemy3EggCount,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ColonyCard extends StatelessWidget {
  const _ColonyCard({
    required this.name,
    required this.color,
    required this.food,
    required this.workers,
    required this.soldiers,
    required this.nurses,
    required this.queens,
    required this.larvae,
    required this.eggs,
  });

  final String name;
  final Color color;
  final int food;
  final int workers;
  final int soldiers;
  final int nurses;
  final int queens;
  final int larvae;
  final int eggs;

  @override
  Widget build(BuildContext context) {
    final total = workers + soldiers + nurses + queens + larvae + eggs;

    return Card(
      color: Colors.grey.shade800,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$name ($total)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const Spacer(),
                Icon(
                  Icons.restaurant,
                  size: 14,
                  color: Colors.lightGreenAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  '$food',
                  style: const TextStyle(color: Colors.lightGreenAccent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (queens > 0) _CasteChip('Q', queens, Colors.purpleAccent),
                _CasteChip('W', workers, Colors.white70),
                _CasteChip('S', soldiers, Colors.orangeAccent),
                _CasteChip('N', nurses, Colors.pinkAccent),
                if (larvae > 0) _CasteChip('L', larvae, Colors.white54),
                if (eggs > 0) _CasteChip('E', eggs, Colors.yellow.shade200),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CasteChip extends StatelessWidget {
  const _CasteChip(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        Text('$count', style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _MobileSettingsContent extends StatefulWidget {
  const _MobileSettingsContent({required this.simulation, required this.game});

  final ColonySimulation simulation;
  final AntWorldGame game;

  @override
  State<_MobileSettingsContent> createState() => _MobileSettingsContentState();
}

class _MobileSettingsContentState extends State<_MobileSettingsContent> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // Overlays section
        const Text(
          'Overlays',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.foodPheromonesVisible,
          builder: (context, visible, _) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Food Pheromones'),
              subtitle: const Text('Blue trails from food carriers'),
              value: visible,
              onChanged: (v) => widget.simulation.setFoodPheromoneVisibility(v),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.homePheromonesVisible,
          builder: (context, visible, _) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Home Pheromones'),
              subtitle: const Text('Gray trails from foragers'),
              value: visible,
              onChanged: (v) => widget.simulation.setHomePheromoneVisibility(v),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.foodScentVisible,
          builder: (context, visible, _) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Food Scent Clouds'),
              subtitle: const Text('Visualize diffusing scent'),
              value: visible,
              onChanged: (v) => widget.simulation.setFoodScentVisibility(v),
            );
          },
        ),
        const Divider(),
        // Behavior section
        const Text(
          'Behavior',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow Resting'),
          subtitle: const Text('Ants take micro-naps to recover energy'),
          value: widget.simulation.config.restEnabled,
          onChanged: (v) {
            setState(() => widget.simulation.setRestingEnabled(v));
          },
        ),
        const SizedBox(height: 16),
        // Camera
        const Text(
          'Camera',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Zoom: '),
            Expanded(
              child: Slider(
                value: widget.game.zoomFactor,
                min: 0.1,
                max: 5.0,
                onChanged: (v) {
                  widget.game.setZoom(v);
                  setState(() {});
                },
              ),
            ),
            Text('${widget.game.zoomFactor.toStringAsFixed(1)}x'),
          ],
        ),
        TextButton.icon(
          onPressed: () {
            widget.game.refreshViewport();
            setState(() {});
          },
          icon: const Icon(Icons.zoom_out_map),
          label: const Text('Reset View'),
        ),
      ],
    );
  }
}
