import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/game_state_manager.dart';
import '../core/god_actions_controller.dart';
import '../core/game_mode.dart';
import '../core/mode_config.dart';
import '../game/ant_world_game.dart';
import '../services/analytics_service.dart';
import '../simulation/ant.dart';
import '../simulation/colony_simulation.dart';
import '../simulation/world_generator.dart';
import '../simulation/world_grid.dart';
import '../simulation/room_blueprint.dart';

class AntHud extends StatefulWidget {
  const AntHud({
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
  State<AntHud> createState() => _AntHudState();
}

class _AntHudState extends State<AntHud> {
  // Which drawer is currently open (null = all closed)
  int? _openDrawer; // 0 = stats, 1 = controls, 2 = settings, 3 = game
  late int _pendingCols;
  late int _pendingRows;
  bool _saving = false;
  bool _generatingMap = false;
  String _selectedMapSize = 'Medium';
  int _selectedColonyCount = 2;

  @override
  void initState() {
    super.initState();
    _pendingCols = widget.simulation.config.cols;
    _pendingRows = widget.simulation.config.rows;
  }

  void _toggleDrawer(int index) {
    setState(() {
      _openDrawer = _openDrawer == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSandbox = widget.gameStateManager.currentMode == GameMode.sandbox;
    debugPrint(
      'AntHud active: platform=${defaultTargetPlatform.name} '
      'kIsWeb=$kIsWeb size=${MediaQuery.of(context).size}',
    );
    return Positioned.fill(
      child: Stack(
        children: [
          // Left-side drawer tabs
          _buildDrawerTabs(context),
          // Drawer panels
          _buildStatsDrawer(context),
          _buildControlsDrawer(context, isSandbox: isSandbox),
          _buildSettingsDrawer(context, isSandbox: isSandbox),
          _buildGameDrawer(context, isSandbox: isSandbox),
          _buildGoalOverlay(context),
          _buildGodActionsPanel(context),
          _buildPerfBadge(context),
          // Selected ant panel (stays separate)
          _buildSelectedAntPanel(context),
        ],
      ),
    );
  }

  Widget _buildGoalOverlay(BuildContext context) {
    final config = widget.gameStateManager.currentConfig;
    if (config == null) return const SizedBox.shrink();
    final objective = (config is CampaignLevelConfig)
        ? config.objective.description
        : 'Survive and thrive';
    final levelLabel = (config is CampaignLevelConfig)
        ? config.levelId
        : config.mode.displayName;
    return Positioned(
      top: 12,
      left: 72, // clear left tabs
      right: 180, // leave room for right-side buttons
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Card(
            color: Colors.black.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    levelLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    objective,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Food: ${widget.simulation.foodCollected.value} • Day ${widget.simulation.daysPassed.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPerfBadge(BuildContext context) {
    return Positioned(
      top: 70,
      right: 16,
      child: ValueListenableBuilder<PerfSample>(
        valueListenable: widget.game.perfStats,
        builder: (context, perf, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              'FPS ${perf.fps.toStringAsFixed(0)} • upd ${perf.updateMs.toStringAsFixed(1)}ms',
              style: const TextStyle(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGodActionsPanel(BuildContext context) {
    final controller = widget.gameStateManager.godActions;
    return Positioned(
      right: 12,
      bottom: 16,
      child: StreamBuilder<void>(
        stream: controller.changes,
        builder: (context, _) {
          return Card(
            color: Colors.black.withValues(alpha: 0.65),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _godActionButton(
                    context,
                    controller,
                    GodActionType.digBurst,
                    'Dig Burst',
                    Icons.construction,
                    () => controller.use(
                      GodActionType.digBurst,
                      widget.simulation,
                    ),
                  ),
                  _godActionButton(
                    context,
                    controller,
                    GodActionType.foodDrop,
                    'Food Drop',
                    Icons.restaurant,
                    () => controller.use(
                      GodActionType.foodDrop,
                      widget.simulation,
                    ),
                  ),
                  _godActionButton(
                    context,
                    controller,
                    GodActionType.rockWall,
                    'Rock Wall',
                    Icons.shield,
                    () => controller.use(
                      GodActionType.rockWall,
                      widget.simulation,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _godActionButton(
    BuildContext context,
    GodActionsController controller,
    GodActionType type,
    String label,
    IconData icon,
    Future<void> Function() onUse,
  ) {
    final state = controller.state(type);
    final remaining = controller.cooldownRemaining(type);
    final cooldownText = remaining == Duration.zero
        ? 'Ready'
        : '${remaining.inSeconds}s';
    final canUse = controller.canUse(type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Flex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: ElevatedButton.icon(
              onPressed: canUse ? onUse : null,
              icon: Icon(icon, size: 16),
              label: Text('$label (${state.charges}/${state.maxCharges})'),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(cooldownText, style: const TextStyle(fontSize: 11)),
              TextButton(
                onPressed: () => controller.watchAdForCharge(type),
                child: const Text('+1 via ad', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTabs(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final tabs = <Widget>[
      _DrawerTab(
        icon: Icons.bar_chart,
        label: 'Stats',
        isActive: _openDrawer == 0,
        onTap: () => _toggleDrawer(0),
        colorScheme: colorScheme,
      ),
      const SizedBox(height: 8),
      _DrawerTab(
        icon: Icons.gamepad,
        label: 'Controls',
        isActive: _openDrawer == 1,
        onTap: () => _toggleDrawer(1),
        colorScheme: colorScheme,
      ),
      const SizedBox(height: 8),
      _DrawerTab(
        icon: Icons.tune,
        label: 'Settings',
        isActive: _openDrawer == 2,
        onTap: () => _toggleDrawer(2),
        colorScheme: colorScheme,
      ),
      const SizedBox(height: 8),
      _DrawerTab(
        icon: Icons.menu,
        label: 'Game',
        isActive: _openDrawer == 3,
        onTap: () => _toggleDrawer(3),
        colorScheme: colorScheme,
      ),
    ];

    return Positioned(left: 0, top: 16, child: Column(children: tabs));
  }

  double _drawerWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive width: max 320, min 200, or 70% of screen on small devices
    return (screenWidth * 0.7).clamp(200.0, 320.0);
  }

  Widget _buildStatsDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = _openDrawer == 0;
    final width = _drawerWidth(context);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: isOpen ? 48 : -width,
      top: 16,
      bottom: 16,
      child: SizedBox(
        width: width,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDrawerHeader(
                  'Stats',
                  Icons.bar_chart,
                  () => _toggleDrawer(0),
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: _StatsPanelContent(simulation: widget.simulation),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsDrawer(BuildContext context, {required bool isSandbox}) {
    final theme = Theme.of(context);
    final isOpen = _openDrawer == 1;
    final width = _drawerWidth(context);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: isOpen ? 48 : -width,
      top: 16,
      bottom: 16,
      child: SizedBox(
        width: width,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDrawerHeader(
                  'Controls',
                  Icons.gamepad,
                  () => _toggleDrawer(1),
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildControlsContent(theme, isSandbox),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsDrawer(BuildContext context, {required bool isSandbox}) {
    final theme = Theme.of(context);
    final isOpen = _openDrawer == 2;
    final width = _drawerWidth(context);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: isOpen ? 48 : -width,
      top: 16,
      bottom: 16,
      child: SizedBox(
        width: width,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDrawerHeader(
                  'Settings',
                  Icons.tune,
                  () => _toggleDrawer(2),
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ant Tuning
                        _buildTuningControls(theme, isSandbox: isSandbox),
                        const Divider(),
                        if (isSandbox) ...[
                          // World Generation
                          _buildGenerationControls(theme),
                          const SizedBox(height: 8),
                          _buildGridControls(theme),
                          const Divider(),
                        ],
                        // Utilities
                        _buildFoodControls(),
                        const SizedBox(height: 12),
                        // Help
                        _buildDocsSection(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameDrawer(BuildContext context, {required bool isSandbox}) {
    final theme = Theme.of(context);
    final isOpen = _openDrawer == 3;
    final width = _drawerWidth(context);
    final allowSave = widget.gameStateManager.currentConfig?.allowSave ?? false;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: isOpen ? 48 : -width,
      top: 16,
      bottom: 16,
      child: SizedBox(
        width: width,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDrawerHeader('Game', Icons.menu, () => _toggleDrawer(3)),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Save & Load', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _saving || !allowSave ? null : _saveWorld,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            !allowSave
                                ? 'Saving disabled for this mode'
                                : (_saving ? 'Saving...' : 'Save Game'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const Divider(height: 32),
                        Text('Exit', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        const Text(
                          'Quit to menu will clear all unsaved progress.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _confirmQuit,
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Quit to Menu'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmQuit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit Game?'),
        content: const Text('Any unsaved progress will be lost. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Quit'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Clean up simulation memory
      widget.simulation.prepareForNewWorld();
      widget.game.invalidateTerrainLayer();

      // Call the quit callback
      widget.onQuitToMenu?.call();
    }
  }

  Widget _buildDrawerHeader(String title, IconData icon, VoidCallback onClose) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      ],
    );
  }

  Widget _buildControlsContent(ThemeData theme, bool isSandbox) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ControlSection(
          title: 'Simulation Flow',
          icon: Icons.play_circle_fill,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPauseButton(),
              const SizedBox(height: 12),
              _buildSpeedControls(theme),
              const SizedBox(height: 12),
              _buildBehaviorControls(theme, isSandbox: isSandbox),
            ],
          ),
        ),
        _ControlSection(
          title: 'Editing Tools',
          icon: Icons.app_registration,
          child: _buildEditTools(theme),
        ),
        _ControlSection(
          title: 'Room Painter',
          icon: Icons.brush,
          child: _buildRoomPainterControls(theme),
        ),
        _ControlSection(
          title: 'Camera & View',
          icon: Icons.center_focus_strong,
          child: _buildViewControls(theme),
        ),
        _ControlSection(
          title: 'Overlays',
          icon: Icons.layers,
          child: _buildOverlayControls(theme),
        ),
        _ControlSection(
          title: 'Population',
          icon: Icons.groups,
          child: _buildPopulationControls(theme),
        ),
      ],
    );
  }

  Widget _buildSelectedAntPanel(BuildContext context) {
    return ValueListenableBuilder<Ant?>(
      valueListenable: widget.game.selectedAnt,
      builder: (context, ant, _) {
        if (ant == null) return const SizedBox.shrink();

        return Positioned(
          left: 16,
          top: 80,
          child: _AntDetailsPanel(
            ant: ant,
            simulation: widget.simulation,
            onClose: widget.game.clearSelection,
          ),
        );
      },
    );
  }

  Widget _buildDocsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Field Guide', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text(
          'Open the in-game handbook to learn how ants forage, rest, and follow pheromones.',
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _openDocs,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Open Docs'),
        ),
      ],
    );
  }

  Future<void> _openDocs() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                children: const [
                  _DocHeading(title: 'Colony Primer'),
                  SizedBox(height: 8),
                  Text(
                    'Each ant runs a simple state machine: forage, return home, or rest. '
                    'When resting is enabled, energy drains over time. Ants head back to the nest when '
                    'energy runs out, take a quick micro-nap (waking at 70% energy), then resume work. '
                    'This mirrors real ants who take ~250 short naps daily while 80% of the colony stays active. '
                    'Click any ant to see its real-time stats.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Explorers & Movement'),
                  SizedBox(height: 8),
                  Text(
                    'About 5% of ants spawn as explorers. Explorers ignore pheromone input more often '
                    'and inject random turns, allowing the colony to find new food pockets. '
                    'Regular ants prioritize following pheromone trails using three forward sensors. '
                    'They only use direct food sensing when no pheromone trails are nearby.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Pheromone Network'),
                  SizedBox(height: 8),
                  Text(
                    'Ants drop home pheromones while foraging and food pheromones when carrying food. '
                    'The grid stores two Float32 layers that decay each frame based on the decay slider. '
                    'Toggle "Show Pheromones" to see trails: blue for food, gray for home. '
                    'Stronger deposit values create more robust highways that attract more followers.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Rival Colonies'),
                  SizedBox(height: 8),
                  Text(
                    'Two colonies compete for resources on the map. Each colony has its own nest and queen. '
                    'When ants from different colonies meet, combat may occur based on their aggression level. '
                    'Soldiers are aggressive (90% fight chance), workers less so (20%), nurses flee (10%). '
                    'Both sides have attack, defense, and health stats – collisions trigger duels until one ant dies.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'World Generation'),
                  SizedBox(height: 8),
                  Text(
                    'Random maps generate a 400×400 grid filled with dirt, then carve tunnels and caverns. '
                    'Obstacles include organic formations: tree roots (branching lines), boulder clusters, '
                    'and mineral veins (long curved barriers). Food clusters are scattered throughout. '
                    'The nest spawns in the lower portion of the map.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Obstacles & Digging'),
                  SizedBox(height: 8),
                  Text(
                    'When ants collide with dirt, they dig by spending energy. Rocks block movement entirely. '
                    'You can paint cells using the brush modes: Dig clears terrain, Food places food clusters, '
                    'Rock creates impassable barriers. Shift+click or right-click always places food.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Stuck Detection'),
                  SizedBox(height: 8),
                  Text(
                    'Ants that fail to move for 30 seconds (except when resting) are removed from the simulation. '
                    'This prevents ants from getting permanently trapped in unreachable areas.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Tips'),
                  SizedBox(height: 8),
                  Text(
                    '• Use Random Map to reroll cave layouts and food clusters.\n'
                    '• Hover over (i) icons in settings to learn what each slider does.\n'
                    '• Higher pheromone decay values (closer to 1.0) create longer-lasting trails.\n'
                    '• Click ants to track individuals and watch their behavior in real-time.\n'
                    '• Disable resting to keep ants active, but they won\'t recover energy.',
                  ),
                  SizedBox(height: 24),
                  Center(child: Icon(Icons.expand_more, color: Colors.white54)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPopulationControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Population', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ValueListenableBuilder<int>(
          valueListenable: widget.simulation.antCount,
          builder: (context, count, _) => Text('Current: $count'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PopulationButton(
              label: '-10',
              onPressed: () => widget.simulation.removeAnts(10),
            ),
            _PopulationButton(
              label: '-1',
              onPressed: () => widget.simulation.removeAnts(1),
            ),
            _PopulationButton(
              label: '+1',
              onPressed: () => widget.simulation.addAnts(1),
            ),
            _PopulationButton(
              label: '+10',
              onPressed: () => widget.simulation.addAnts(10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Speed', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ValueListenableBuilder<double>(
          valueListenable: widget.simulation.antSpeedMultiplier,
          builder: (context, multiplier, _) {
            const double base = 0.2;
            final display = (multiplier / base).clamp(0.5, 15.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Speed: ${display.toStringAsFixed(1)}x'),
                Slider(
                  value: display,
                  min: 1.0,
                  max: 10.0,
                  divisions: 18,
                  label: '${display.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    widget.simulation.setAntSpeedMultiplier(value * base);
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildBehaviorControls(ThemeData theme, {required bool isSandbox}) {
    final allowResting = widget.simulation.config.restEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Behavior', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow Resting'),
          subtitle: Text(
            isSandbox
                ? 'Disable to keep ants active at all times.'
                : 'Locked in this mode for fairness.',
          ),
          value: allowResting,
          onChanged: isSandbox
              ? (value) {
                  setState(() {
                    widget.simulation.setRestingEnabled(value);
                  });
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildTuningControls(ThemeData theme, {required bool isSandbox}) {
    final config = widget.simulation.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Behavior Tuning', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (isSandbox)
          _ConfigSlider(
            label: 'Explorer Ants',
            tooltip:
                'Percentage of ants that ignore pheromones and wander randomly to discover new food sources.',
            value: config.explorerRatio,
            min: 0,
            max: 0.5,
            divisions: 50,
            displayValue: (v) => '${(v * 100).toStringAsFixed(0)}%',
            onChanged: (value) {
              setState(() {
                widget.simulation.setExplorerRatio(value);
              });
            },
          )
        else
          const Text(
            'Behavior tuning locked for this mode.',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        _ConfigSlider(
          label: 'Random Turn Strength',
          tooltip:
              'How sharply ants turn randomly each step. Higher values create more erratic movement.',
          value: config.randomTurnStrength,
          min: 0.2,
          max: 2.5,
          divisions: 46,
          displayValue: (v) => '${v.toStringAsFixed(2)} rad',
          onChanged: (value) {
            setState(() {
              widget.simulation.setRandomTurnStrength(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Sensor Distance',
          tooltip:
              'How far ahead ants sense pheromones. Longer range helps follow distant trails.',
          value: config.sensorDistance,
          min: 2,
          max: 16,
          divisions: 28,
          displayValue: (v) => '${v.toStringAsFixed(1)} cells',
          onChanged: (value) {
            setState(() {
              widget.simulation.setSensorDistance(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Sensor Angle',
          tooltip:
              'Spread angle between left/right sensors. Wider angles detect broader areas but may miss narrow trails.',
          value: config.sensorAngle,
          min: 0.2,
          max: 1.2,
          divisions: 50,
          displayValue: (v) => '${(v * 180 / math.pi).toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() {
              widget.simulation.setSensorAngle(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Food Deposit Strength',
          tooltip:
              'How much food pheromone ants drop when carrying food. Stronger trails attract more followers.',
          value: config.foodDepositStrength,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          displayValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            setState(() {
              widget.simulation.setFoodDepositStrength(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Home Deposit Strength',
          tooltip:
              'How much home pheromone foraging ants drop. Helps returning ants find their way back.',
          value: config.homeDepositStrength,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          displayValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            setState(() {
              widget.simulation.setHomeDepositStrength(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Food Sense Range',
          tooltip:
              'Maximum distance ants can directly detect food (without pheromones). Only used when no trails nearby.',
          value: config.foodSenseRange,
          min: 20,
          max: 200,
          divisions: 18,
          displayValue: (v) => '${v.toStringAsFixed(0)} cells',
          onChanged: (value) {
            setState(() {
              widget.simulation.setFoodSenseRange(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Pheromone Decay / Frame',
          tooltip:
              'Multiplier applied to pheromones each frame. Higher = longer-lasting trails (0.99 = slow decay).',
          value: config.decayPerFrame,
          min: 0.90,
          max: 0.999,
          divisions: 99,
          displayValue: (v) => v.toStringAsFixed(3),
          onChanged: (value) {
            setState(() {
              widget.simulation.setDecayPerFrame(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Decay Threshold',
          tooltip:
              'Pheromone level below which trails are removed. Higher values clean up weak trails faster.',
          value: config.decayThreshold,
          min: 0.0,
          max: 0.1,
          divisions: 50,
          displayValue: (v) => v.toStringAsFixed(3),
          onChanged: (value) {
            setState(() {
              widget.simulation.setDecayThreshold(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Energy Capacity',
          tooltip:
              'Maximum energy an ant can store. Higher capacity means longer foraging trips before resting.',
          value: config.energyCapacity,
          min: 20,
          max: 300,
          divisions: 28,
          displayValue: (v) => '${v.toStringAsFixed(0)} energy',
          onChanged: (value) {
            setState(() {
              widget.simulation.setEnergyCapacity(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Energy Decay / sec',
          tooltip:
              'Energy lost per second while moving. Set to 0 for infinite stamina.',
          value: config.energyDecayPerSecond,
          min: 0,
          max: 5,
          divisions: 25,
          displayValue: (v) => v.toStringAsFixed(2),
          onChanged: (value) {
            setState(() {
              widget.simulation.setEnergyDecayRate(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Energy Recovery / sec',
          tooltip:
              'Energy gained per second while resting. Ants wake at 70% capacity (micro-naps like real ants).',
          value: config.energyRecoveryPerSecond,
          min: 0.5,
          max: 10,
          divisions: 19,
          displayValue: (v) => v.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              widget.simulation.setEnergyRecoveryRate(value);
            });
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(widget.simulation.resetBehaviorDefaults);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset to Defaults'),
          ),
        ),
      ],
    );
  }

  Widget _buildFoodControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Food Utilities',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () =>
              widget.simulation.scatterFood(clusters: 8, radius: 3),
          icon: const Icon(Icons.local_florist_outlined),
          label: const Text('Scatter Random Food'),
        ),
      ],
    );
  }

  Widget _buildGenerationControls(ThemeData theme) {
    final seed = widget.simulation.lastSeed;
    final current = widget.simulation.config;
    final presets = WorldGenerator.presets;
    final selectedSize = presets[_selectedMapSize]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map Generation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Current: ${current.cols}×${current.rows}'),
        Text(
          seed == null ? 'Seed: --' : 'Seed: $seed',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Size: '),
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButton<String>(
                value: _selectedMapSize,
                isDense: true,
                isExpanded: true,
                items: presets.keys.map((name) {
                  final size = presets[name]!;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(
                      '$name (${size.$1}×${size.$2})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedMapSize = value);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Colonies: '),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _selectedColonyCount,
              isDense: true,
              items: [1, 2, 3, 4].map((count) {
                return DropdownMenuItem(value: count, child: Text('$count'));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedColonyCount = value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _generatingMap ? null : _randomizeMap,
          icon: _generatingMap
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(
            _generatingMap
                ? 'Generating...'
                : 'New Colony (${selectedSize.$1}×${selectedSize.$2})',
          ),
        ),
      ],
    );
  }

  Widget _buildGridControls(ThemeData theme) {
    final current = widget.simulation.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grid Size', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Current: ${current.cols} × ${current.rows}'),
        const SizedBox(height: 12),
        Text('Columns ($_pendingCols)'),
        Slider(
          min: 40,
          max: 160,
          divisions: 12,
          value: _pendingCols.toDouble().clamp(40, 160),
          onChanged: (value) => setState(() => _pendingCols = value.round()),
        ),
        Text('Rows ($_pendingRows)'),
        Slider(
          min: 30,
          max: 140,
          divisions: 11,
          value: _pendingRows.toDouble().clamp(30, 140),
          onChanged: (value) => setState(() => _pendingRows = value.round()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _applyGridSize,
          icon: const Icon(Icons.map),
          label: const Text('Apply Grid Size'),
        ),
      ],
    );
  }

  Widget _buildViewControls(ThemeData theme) {
    final zoom = widget.game.zoomFactor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('View', style: theme.textTheme.titleSmall),
        Text('Zoom: ${zoom.toStringAsFixed(2)}x'),
        Slider(
          min: 0.1,
          max: 5.0,
          divisions: 49,
          value: zoom,
          onChanged: (value) {
            widget.game.setZoom(value);
            setState(() {});
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _resetCamera,
            icon: const Icon(Icons.zoom_out_map),
            label: const Text('Reset View'),
          ),
        ),
      ],
    );
  }

  Widget _buildPauseButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.simulation.paused,
      builder: (context, isPaused, _) {
        return FilledButton.icon(
          onPressed: widget.simulation.togglePause,
          icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
          label: Text(isPaused ? 'Resume simulation' : 'Pause simulation'),
          style: FilledButton.styleFrom(
            backgroundColor: isPaused ? Colors.green : Colors.orange,
            minimumSize: const Size(double.infinity, 48),
          ),
        );
      },
    );
  }

  Widget _buildEditTools(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.game.editMode,
          builder: (context, editing, _) {
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Edit Mode'),
              subtitle: Text(
                editing
                    ? 'Tap or drag on the map to modify terrain.'
                    : 'Locked to navigation controls only.',
                style: theme.textTheme.bodySmall,
              ),
              value: editing,
              onChanged: (value) {
                widget.game.editMode.value = value;
              },
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Brush Mode', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ValueListenableBuilder<BrushMode>(
          valueListenable: widget.game.brushMode,
          builder: (context, mode, _) {
            return SegmentedButton<BrushMode>(
              segments: const [
                ButtonSegment(
                  value: BrushMode.dig,
                  label: Text('Dig'),
                  icon: Icon(Icons.construction),
                ),
                ButtonSegment(
                  value: BrushMode.food,
                  label: Text('Food'),
                  icon: Icon(Icons.fastfood_outlined),
                ),
                ButtonSegment(
                  value: BrushMode.rock,
                  label: Text('Rock'),
                  icon: Icon(Icons.landscape_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  widget.game.setBrushMode(selection.first);
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: enable Edit Mode, pick a brush, then drag to sculpt tunnels or drop resources.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRoomPainterControls(ThemeData theme) {
    final manager = widget.simulation.blueprintManager;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Room Type', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PainterButton(
              label: 'Nursery',
              icon: Icons.baby_changing_station,
              onPressed: () => manager.startPainting(RoomType.nursery, 0),
            ),
            _PainterButton(
              label: 'Food Storage',
              icon: Icons.restaurant,
              onPressed: () => manager.startPainting(RoomType.foodStorage, 0),
            ),
            _PainterButton(
              label: 'Barracks',
              icon: Icons.shield,
              onPressed: () => manager.startPainting(RoomType.barracks, 0),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Drag on dirt to paint the outline. Builders will carve a tunnel and room matching the painted footprint.',
          style: TextStyle(fontSize: 12),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, color: Colors.orangeAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Colonies now begin with only a queen chamber. Plan nurseries, food storage, and barracks yourself.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<RoomPainterState>(
          valueListenable: manager.painterState,
          builder: (context, state, _) {
            final isPainting = state.isPainting;
            final roomLabel = state.roomType != null
                ? _roomTypeLabel(state.roomType!)
                : 'No room selected';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPainting
                      ? 'Painting $roomLabel'
                      : 'Tap a room type to begin painting.',
                ),
                Text('Selected tiles: ${state.cellCount}'),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      state.errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: isPainting ? _finishBlueprintPainting : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Finish Blueprint'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: isPainting ? manager.cancelPainting : null,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const Divider(height: 24),
        ValueListenableBuilder<int>(
          valueListenable: manager.revision,
          builder: (context, value, child) {
            return _buildBlueprintQueue(theme);
          },
        ),
      ],
    );
  }

  Widget _buildBlueprintQueue(ThemeData theme) {
    final queue = widget.simulation.blueprintManager.blueprints;
    if (queue.isEmpty) {
      return const Text('No queued blueprints yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Queued Blueprints', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ...queue.map((blueprint) => _buildBlueprintTile(theme, blueprint)),
      ],
    );
  }

  Widget _buildBlueprintTile(ThemeData theme, RoomBlueprint blueprint) {
    final progress = blueprint
        .buildProgress(widget.simulation.world)
        .clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text('$percent%', style: const TextStyle(fontSize: 10)),
        ),
        title: Text(
          '${_roomTypeLabel(blueprint.type)} • ${_blueprintStatusText(blueprint.status)}',
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: progress, minHeight: 6),
        ),
        trailing: IconButton(
          tooltip: 'Cancel blueprint',
          icon: const Icon(Icons.close),
          onPressed: () => widget.simulation.cancelBlueprint(blueprint.id),
        ),
      ),
    );
  }

  void _finishBlueprintPainting() {
    final result = widget.simulation.blueprintManager.finishPainting(
      widget.simulation.world,
    );
    final messenger = ScaffoldMessenger.of(context);
    if (!result.success) {
      if (result.error != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.error!),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
      return;
    }
    final blueprint = result.blueprint;
    if (blueprint != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_roomTypeLabel(blueprint.type)} blueprint queued. Builders are on the way.',
          ),
        ),
      );
    }
  }

  String _roomTypeLabel(RoomType type) {
    switch (type) {
      case RoomType.home:
        return 'Hatchery';
      case RoomType.nursery:
        return 'Nursery';
      case RoomType.foodStorage:
        return 'Food Storage';
      case RoomType.barracks:
        return 'Barracks';
    }
  }

  String _blueprintStatusText(RoomBlueprintStatus status) {
    switch (status) {
      case RoomBlueprintStatus.pending:
        return 'pending';
      case RoomBlueprintStatus.queued:
        return 'queued';
      case RoomBlueprintStatus.digging:
        return 'digging';
      case RoomBlueprintStatus.complete:
        return 'complete';
      case RoomBlueprintStatus.cancelled:
        return 'cancelled';
      case RoomBlueprintStatus.rejected:
        return 'rejected';
    }
  }

  Widget _buildOverlayControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.foodPheromonesVisible,
          builder: (context, visible, _) {
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Food Pheromone Trails'),
              subtitle: const Text('Blue trails laid while carrying food.'),
              value: visible,
              onChanged: widget.simulation.setFoodPheromoneVisibility,
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.homePheromonesVisible,
          builder: (context, visible, _) {
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Home Pheromone Trails'),
              subtitle: const Text(
                'Gray guidance left by foragers heading home.',
              ),
              value: visible,
              onChanged: widget.simulation.setHomePheromoneVisibility,
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.pheromonesVisible,
          builder: (context, showAny, _) {
            return Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    widget.simulation.setPheromoneVisibility(!showAny),
                icon: Icon(
                  showAny ? Icons.visibility_off : Icons.visibility_outlined,
                ),
                label: Text(
                  showAny ? 'Hide all pheromones' : 'Show all pheromones',
                ),
              ),
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<bool>(
          valueListenable: widget.simulation.foodScentVisible,
          builder: (context, visible, _) {
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Food Scent Clouds'),
              subtitle: const Text(
                'Visualize diffusing scent hints through tunnels.',
              ),
              value: visible,
              onChanged: (value) {
                widget.simulation.setFoodScentVisibility(value);
              },
            );
          },
        ),
      ],
    );
  }

  void _applyGridSize() {
    if (_pendingCols == widget.simulation.config.cols &&
        _pendingRows == widget.simulation.config.rows) {
      return;
    }
    widget.simulation.resizeWorld(cols: _pendingCols, rows: _pendingRows);
    widget.game.refreshViewport();
    setState(() {
      _pendingCols = widget.simulation.config.cols;
      _pendingRows = widget.simulation.config.rows;
    });
  }

  void _resetCamera() {
    widget.game.refreshViewport();
    setState(() {});
  }

  Future<void> _saveWorld() async {
    setState(() => _saving = true);
    final success = await widget.gameStateManager.saveCurrentGame();
    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      AnalyticsService.instance.logGameSaved(
        daysPassed: widget.simulation.daysPassed.value,
        antCount: widget.simulation.ants.length,
        totalFood: widget.simulation.foodCollected.value,
      );
      widget.onGameSaved?.call();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'World saved' : 'Failed to save world')),
    );
  }

  Future<void> _randomizeMap() async {
    setState(() => _generatingMap = true);

    // Get selected map size
    final size = WorldGenerator.presets[_selectedMapSize]!;
    final cols = size.$1;
    final rows = size.$2;

    // Clean up existing simulation first (clear 1000s of ants, free old world memory)
    widget.simulation.prepareForNewWorld();
    widget.game.invalidateTerrainLayer();

    // Allow UI to update and give GC time to reclaim memory
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final seed = math.Random().nextInt(0x7fffffff);

    try {
      // Generate new world with selected size and colony count
      widget.simulation.generateRandomWorld(
        seed: seed,
        cols: cols,
        rows: rows,
        colonyCount: _selectedColonyCount,
      );
      widget.game.invalidateTerrainLayer();
      widget.game.refreshViewport();

      // Track map generation
      AnalyticsService.instance.logMapGenerated(
        sizePreset: _selectedMapSize,
        cols: cols,
        rows: rows,
        colonyCount: _selectedColonyCount,
        seed: seed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingMap = false;
          _pendingCols = widget.simulation.config.cols;
          _pendingRows = widget.simulation.config.rows;
        });
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Generated new world (seed $seed)')));
  }
}

class _PopulationButton extends StatelessWidget {
  const _PopulationButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

class _PainterButton extends StatelessWidget {
  const _PainterButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.6,
    );
    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DocHeading extends StatelessWidget {
  const _DocHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    required this.displayValue,
    this.tooltip,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) displayValue;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(label)),
                  if (tooltip != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: tooltip!,
                      preferBelow: false,
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayValue(clampedValue),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          value: clampedValue,
          min: min,
          max: max,
          divisions: divisions,
          label: displayValue(clampedValue),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Tab button that sits half-outside the left edge of the screen
class _DrawerTab extends StatelessWidget {
  const _DrawerTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-24, 0), // Half outside the screen
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Icon(
              icon,
              color: isActive
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// Stats panel content for use inside a drawer
class _StatsPanelContent extends StatefulWidget {
  const _StatsPanelContent({required this.simulation});

  final ColonySimulation simulation;

  @override
  State<_StatsPanelContent> createState() => _StatsPanelContentState();
}

class _StatsPanelContentState extends State<_StatsPanelContent> {
  late final Stream<void> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(milliseconds: 200));
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}m ${secs}s';
  }

  // Colony colors: red, yellow, blue, white
  static const _colonyColors = [
    Color(0xFFF44336), // Red (Colony 0)
    Color(0xFFFFEB3B), // Yellow (Colony 1)
    Color(0xFF2196F3), // Blue (Colony 2)
    Color(0xFFFFFFFF), // White (Colony 3)
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sim = widget.simulation;
    final colonyCount = sim.config.colonyCount;

    return StreamBuilder<void>(
      stream: _ticker,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Time row
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Day ${sim.daysPassed.value}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatTime(sim.elapsedTime.value),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Dynamically show colonies based on colonyCount
            if (colonyCount >= 1) ...[
              _buildColonySection(
                theme: theme,
                colonyName: 'Colony 0',
                colonyColor: _colonyColors[0],
                queenCount: sim.queenCount,
                workerCount: sim.workerCount,
                soldierCount: sim.soldierCount,
                nurseCount: sim.nurseCount,
                larvaCount: sim.larvaCount,
                eggCount: sim.eggCount,
                foodCount: sim.colony0Food.value,
              ),
            ],
            if (colonyCount >= 2) ...[
              const SizedBox(height: 16),
              _buildColonySection(
                theme: theme,
                colonyName: 'Colony 1',
                colonyColor: _colonyColors[1],
                queenCount: sim.enemy1QueenCount,
                workerCount: sim.enemy1WorkerCount,
                soldierCount: sim.enemy1SoldierCount,
                nurseCount: sim.enemy1NurseCount,
                larvaCount: sim.enemy1LarvaCount,
                eggCount: sim.enemy1EggCount,
                foodCount: sim.colony1Food.value,
              ),
            ],
            if (colonyCount >= 3) ...[
              const SizedBox(height: 16),
              _buildColonySection(
                theme: theme,
                colonyName: 'Colony 2',
                colonyColor: _colonyColors[2],
                queenCount: sim.enemy2QueenCount,
                workerCount: sim.enemy2WorkerCount,
                soldierCount: sim.enemy2SoldierCount,
                nurseCount: sim.enemy2NurseCount,
                larvaCount: sim.enemy2LarvaCount,
                eggCount: sim.enemy2EggCount,
                foodCount: sim.colony2Food.value,
              ),
            ],
            if (colonyCount >= 4) ...[
              const SizedBox(height: 16),
              _buildColonySection(
                theme: theme,
                colonyName: 'Colony 3',
                colonyColor: _colonyColors[3],
                queenCount: sim.enemy3QueenCount,
                workerCount: sim.enemy3WorkerCount,
                soldierCount: sim.enemy3SoldierCount,
                nurseCount: sim.enemy3NurseCount,
                larvaCount: sim.enemy3LarvaCount,
                eggCount: sim.enemy3EggCount,
                foodCount: sim.colony3Food.value,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildColonySection({
    required ThemeData theme,
    required String colonyName,
    required Color colonyColor,
    required int queenCount,
    required int workerCount,
    required int soldierCount,
    required int nurseCount,
    required int larvaCount,
    required int eggCount,
    required int foodCount,
  }) {
    final totalAnts =
        queenCount +
        workerCount +
        soldierCount +
        nurseCount +
        larvaCount +
        eggCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: colonyColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$colonyName ($totalAnts ants)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colonyColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _StatItem(
              icon: Icons.restaurant,
              label: 'Food',
              value: '$foodCount',
              color: Colors.lightGreenAccent,
            ),
            if (queenCount > 0)
              _StatItem(
                icon: Icons.stars,
                label: 'Queen',
                value: '$queenCount',
                color: Colors.purpleAccent,
              ),
            _StatItem(
              icon: Icons.construction,
              label: 'Workers',
              value: '$workerCount',
            ),
            _StatItem(
              icon: Icons.shield,
              label: 'Soldiers',
              value: '$soldierCount',
              color: Colors.orangeAccent,
            ),
            _StatItem(
              icon: Icons.child_care,
              label: 'Nurses',
              value: '$nurseCount',
              color: Colors.pinkAccent,
            ),
            if (larvaCount > 0)
              _StatItem(
                icon: Icons.egg_alt,
                label: 'Larvae',
                value: '$larvaCount',
                color: Colors.white70,
              ),
            if (eggCount > 0)
              _StatItem(
                icon: Icons.circle,
                label: 'Eggs',
                value: '$eggCount',
                color: Colors.yellow.shade200,
              ),
          ],
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.white70),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$value $label',
            style: TextStyle(fontSize: 12, color: color ?? Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AntDetailsPanel extends StatefulWidget {
  const _AntDetailsPanel({
    required this.ant,
    required this.simulation,
    required this.onClose,
  });

  final Ant ant;
  final ColonySimulation simulation;
  final VoidCallback onClose;

  @override
  State<_AntDetailsPanel> createState() => _AntDetailsPanelState();
}

class _AntDetailsPanelState extends State<_AntDetailsPanel> {
  late final Stream<void> _ticker;

  @override
  void initState() {
    super.initState();
    // Update every 100ms for real-time stats
    _ticker = Stream.periodic(const Duration(milliseconds: 100));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: _ticker,
      builder: (context, _) {
        final ant = widget.ant;
        return Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        ant.colonyId == 0
                            ? Icons.bug_report
                            : Icons.pest_control,
                        color: ant.colonyId == 0 ? Colors.cyan : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'C${ant.colonyId} #${ant.id}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildProperty('Caste', _casteLabel(ant.caste)),
                  _buildProperty('State', _stateLabel(ant)),
                  _buildProperty(
                    'Age',
                    '${ant.age.toStringAsFixed(0)}s / ${ant.maxLifespan.toStringAsFixed(0)}s',
                  ),
                  if (ant.caste == AntCaste.egg || ant.caste == AntCaste.larva)
                    _buildProperty(
                      'Growth',
                      '${(ant.developmentProgress * 100).toStringAsFixed(0)}%',
                    ),
                  _buildProperty(
                    'Position',
                    '(${ant.position.x.toStringAsFixed(1)}, ${ant.position.y.toStringAsFixed(1)})',
                  ),
                  _buildProperty(
                    'Energy',
                    '${ant.energy.toStringAsFixed(1)} / ${widget.simulation.config.energyCapacity}',
                  ),
                  _buildProperty(
                    'HP',
                    '${ant.hp.toStringAsFixed(1)} / ${ant.maxHp.toStringAsFixed(1)}',
                  ),
                  if (ant.caste != AntCaste.egg &&
                      ant.caste != AntCaste.larva) ...[
                    _buildProperty('Attack', ant.attack.toStringAsFixed(1)),
                    _buildProperty('Defense', ant.defense.toStringAsFixed(1)),
                    _buildProperty('Carrying Food', ant.hasFood ? 'Yes' : 'No'),
                    _buildProperty(
                      'Explorer',
                      '${(ant.explorerTendency * 100).toStringAsFixed(0)}%',
                    ),
                    if (ant.needsRest) _buildProperty('Needs Rest', 'Yes'),
                    _buildProperty(
                      'Stuck Time',
                      ant.stuckTime > 0.1
                          ? '${ant.stuckTime.toStringAsFixed(1)}s'
                          : 'N/A',
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProperty(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _stateLabel(Ant ant) {
    switch (ant.state) {
      case AntState.forage:
        return 'Foraging';
      case AntState.returnHome:
        return 'Returning Home';
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
