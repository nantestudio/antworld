import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/ant_world_game.dart';
import '../simulation/colony_simulation.dart';
import '../state/simulation_storage.dart';

class AntHud extends StatefulWidget {
  const AntHud({
    super.key,
    required this.simulation,
    required this.game,
    required this.storage,
  });

  final ColonySimulation simulation;
  final AntWorldGame game;
  final SimulationStorage storage;

  @override
  State<AntHud> createState() => _AntHudState();
}

class _AntHudState extends State<AntHud> {
  bool _showSettings = false;
  late int _pendingCols;
  late int _pendingRows;
  bool _saving = false;
  bool _generatingMap = false;
  bool _controlsCollapsed = false;

  @override
  void initState() {
    super.initState();
    _pendingCols = widget.simulation.config.cols;
    _pendingRows = widget.simulation.config.rows;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildTopBar(context),
                const Spacer(),
                _buildControls(context),
              ],
            ),
          ),
          _buildSettingsPanel(context),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildStatsRow(context)),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _showSettings = !_showSettings),
          icon: Icon(_showSettings ? Icons.close : Icons.tune),
          label: Text(_showSettings ? 'Close' : 'Settings'),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _StatCard(label: 'Day', listenable: widget.simulation.daysPassed),
          _StatCard(label: 'Ants', listenable: widget.simulation.antCount),
          _StatCard(label: 'Food', listenable: widget.simulation.foodCollected),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final panel = Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: IgnorePointer(
          ignoring: _controlsCollapsed,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            offset: _controlsCollapsed ? const Offset(0, 0.4) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _controlsCollapsed ? 0 : 1,
              child: Card(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Quick Controls',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Hide controls',
                            icon: const Icon(Icons.expand_more),
                            onPressed: () =>
                                setState(() => _controlsCollapsed = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
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
                          ValueListenableBuilder<bool>(
                            valueListenable: widget.simulation.pheromonesVisible,
                            builder: (context, visible, _) {
                              return FilledButton.icon(
                                onPressed: widget.simulation.togglePheromones,
                                icon: Icon(
                                  visible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                label: Text(
                                  visible
                                      ? 'Hide Pheromones'
                                      : 'Show Pheromones',
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final fab = Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          offset: _controlsCollapsed ? Offset.zero : const Offset(-0.6, 0.4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _controlsCollapsed ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsCollapsed,
              child: FloatingActionButton(
                heroTag: 'showControls',
                onPressed: () => setState(() => _controlsCollapsed = false),
                child: const Icon(Icons.more_horiz),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(children: [panel, fab]);
  }

  Widget _buildSettingsPanel(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      top: 16,
      bottom: 16,
      right: _showSettings ? 16 : -360,
      child: SizedBox(
        width: 320,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune),
                      const SizedBox(width: 8),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => setState(() => _showSettings = false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildPopulationControls(theme),
                  const Divider(),
                  _buildSpeedControls(theme),
                  const Divider(),
                  _buildBehaviorControls(theme),
                  const Divider(),
                  _buildTuningControls(theme),
                  const Divider(),
                  _buildViewControls(theme),
                  const Divider(),
                  _buildDocsSection(theme),
                  const Divider(),
                  _buildGenerationControls(theme),
                  const Divider(),
                  _buildFoodControls(),
                  const Divider(),
                  _buildPersistenceControls(),
                  const Divider(),
                  _buildGridControls(theme),
                ],
              ),
            ),
          ),
        ),
      ),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                children: const [
                  _DocHeading(title: 'Colony Primer'),
                  SizedBox(height: 8),
                  Text(
                    'Each ant runs a simple state machine: forage, return home, or rest. '
                    'When resting is enabled, energy drains over time. Ants head back to the nest to rest '
                    'once energy hits zero; otherwise they stay in forage/return loops.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Explorers & Movement'),
                  SizedBox(height: 8),
                  Text(
                    'About 5% of ants spawn as explorers. Explorers ignore pheromone input more often '
                    'and inject random turns, allowing the colony to find new food pockets. '
                    'The rest steer using three forward sensors spaced by the configured sensor angle. '
                    'They follow the strongest pheromone signal unless they recently hit rocks.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Pheromone Network'),
                  SizedBox(height: 8),
                  Text(
                    'Ants drop home pheromones while foraging and food pheromones when carrying food. '
                    'The grid stores two Float32 layers that decay each frame based on the decay slider. '
                    'Visible trails on the map reflect these layers. Clearing obstacles or dirt removes '
                    'pheromones at that location.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Opponents & Raids'),
                  SizedBox(height: 8),
                  Text(
                    'Red enemy colonies raid every 30-70 seconds based on your active population. '
                    'They spawn together at the map edges, dig through dirt, and beeline toward nearby workers. '
                    'Both sides have attack, defense, and health stats – collisions trigger duels until one ant pops. '
                    'Widen choke points and keep guards near the nest to blunt incoming waves.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Obstacles & Digging'),
                  SizedBox(height: 8),
                  Text(
                    'When ants collide with dirt, they dig by spending energy. Rocks block movement, so ants either '
                    'bounce or, rarely, try a smarter sidestep. You can add dirt, food, or rock cells via the quick controls.',
                  ),
                  SizedBox(height: 16),
                  _DocHeading(title: 'Tips'),
                  SizedBox(height: 8),
                  Text(
                    '• Use Random Map to reroll cave layouts and food clusters.\n'
                    '• Increase decay thresholds for stronger pheromone highways.\n'
                    '• Disable resting to keep ants digging nonstop, but they will never recharge.',
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
            _PopulationButton(
              label: 'Spawn Enemies',
              onPressed: widget.simulation.spawnDebugRaid,
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

  Widget _buildBehaviorControls(ThemeData theme) {
    final allowResting = widget.simulation.config.restEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Behavior', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow Resting'),
          subtitle: const Text('Disable to keep ants active at all times.'),
          value: allowResting,
          onChanged: (value) {
            setState(() {
              widget.simulation.setRestingEnabled(value);
            });
          },
        ),
      ],
    );
  }

  Widget _buildTuningControls(ThemeData theme) {
    final config = widget.simulation.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Behavior Tuning', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _ConfigSlider(
          label: 'Explorer Ants',
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
        ),
        _ConfigSlider(
          label: 'Random Turn Strength',
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
          value: config.foodSenseRange,
          min: 10,
          max: 80,
          divisions: 14,
          displayValue: (v) => '${v.toStringAsFixed(0)} cells',
          onChanged: (value) {
            setState(() {
              widget.simulation.setFoodSenseRange(value);
            });
          },
        ),
        _ConfigSlider(
          label: 'Pheromone Decay / Frame',
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
          value: config.energyRecoveryPerSecond,
          min: 0,
          max: 5,
          divisions: 25,
          displayValue: (v) => v.toStringAsFixed(2),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map Generation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(seed == null ? 'Seed: --' : 'Seed: $seed'),
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
          label: Text(_generatingMap ? 'Generating...' : 'Random Map'),
        ),
      ],
    );
  }

  Widget _buildPersistenceControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Persistence',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _saveWorld,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : 'Save World'),
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
        Text('Zoom: ${zoom.toStringAsFixed(1)}x'),
        Slider(
          min: 0.5,
          max: 3.0,
          divisions: 25,
          value: zoom,
          onChanged: (value) {
            widget.game.setZoom(value);
            setState(() {});
          },
        ),
        const Text(
          'Use the slider to zoom the world view.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
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

  Future<void> _saveWorld() async {
    setState(() => _saving = true);
    final success = await widget.storage.save(widget.simulation);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'World saved' : 'Failed to save world')),
    );
  }

  Future<void> _randomizeMap() async {
    setState(() => _generatingMap = true);

    // Clean up existing simulation first (clear 1000s of ants, free old world memory)
    widget.simulation.prepareForNewWorld();
    widget.game.invalidateTerrainLayer();

    // Allow UI to update and give GC time to reclaim memory
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final seed = math.Random().nextInt(0x7fffffff);

    try {
      // Generate new world (cleanup already done, so this won't compete for memory)
      widget.simulation.generateRandomWorld(seed: seed);
      widget.game.invalidateTerrainLayer();
      widget.game.refreshViewport();
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

class _DocHeading extends StatelessWidget {
  const _DocHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
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
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) displayValue;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label)),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.listenable});

  final String label;
  final ValueListenable<int> listenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ValueListenableBuilder<int>(
          valueListenable: listenable,
          builder: (context, value, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
